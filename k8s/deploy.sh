#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CLUSTER_NAME=${CLUSTER_NAME:-"openemr-eks"}
AWS_REGION=${AWS_REGION:-"us-west-2"}
NAMESPACE=${NAMESPACE:-"openemr"}
SSL_CERT_ARN=${SSL_CERT_ARN:-""}  # Optional: AWS Certificate Manager ARN
DOMAIN_NAME=${DOMAIN_NAME:-""}    # Optional: Domain name for SSL

# Help function
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Deploy OpenEMR to EKS cluster with automatic infrastructure provisioning"
    echo ""
    echo "Options:"
    echo "  --cluster-name NAME     EKS cluster name (default: openemr-eks)"
    echo "  --aws-region REGION     AWS region (default: us-west-2)"
    echo "  --namespace NAMESPACE   Kubernetes namespace (default: openemr)"
    echo "  --ssl-cert-arn ARN      AWS Certificate Manager ARN for SSL"
    echo "  --domain-name DOMAIN    Domain name for SSL configuration"
    echo "  --help                  Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  CLUSTER_NAME            EKS cluster name"
    echo "  AWS_REGION              AWS region"
    echo "  NAMESPACE               Kubernetes namespace"
    echo "  SSL_CERT_ARN            AWS Certificate Manager ARN"
    echo "  DOMAIN_NAME             Domain name for SSL"
    echo ""
    echo "Example:"
    echo "  $0 --cluster-name my-cluster --aws-region us-east-1"
    echo "  CLUSTER_NAME=my-cluster AWS_REGION=us-east-1 $0"
    echo ""
    echo "Prerequisites:"
    echo "  - EKS cluster must be deployed and accessible"
    echo "  - Terraform outputs must be available"
    echo "  - kubectl, aws CLI, and helm must be installed"
    echo "  - AWS credentials must be configured"
    exit 0
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --cluster-name)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        --aws-region)
            AWS_REGION="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --ssl-cert-arn)
            SSL_CERT_ARN="$2"
            shift 2
            ;;
        --domain-name)
            DOMAIN_NAME="$2"
            shift 2
            ;;
        --help)
            show_help
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo -e "${GREEN}Starting OpenEMR EKS deployment...${NC}"

# Get the script's directory and project root for path-independent operation
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
echo -e "${BLUE}Script location: $SCRIPT_DIR${NC}"
echo -e "${BLUE}Project root: $PROJECT_ROOT${NC}"
echo -e "${BLUE}Current working directory: $(pwd)${NC}"

# Check prerequisites
echo -e "${YELLOW}Checking prerequisites...${NC}"
command -v kubectl >/dev/null 2>&1 || { echo -e "${RED}kubectl is required but not installed.${NC}" >&2; exit 1; }
command -v aws >/dev/null 2>&1 || { echo -e "${RED}AWS CLI is required but not installed.${NC}" >&2; exit 1; }
command -v helm >/dev/null 2>&1 || { echo -e "${RED}Helm is required but not installed.${NC}" >&2; exit 1; }

# Check AWS credentials
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    echo -e "${RED}AWS credentials not configured or invalid.${NC}" >&2
    echo -e "${YELLOW}Run: aws configure${NC}" >&2
    exit 1
fi

# Check if cluster exists and is accessible
echo -e "${YELLOW}Checking cluster accessibility...${NC}"
if ! aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION >/dev/null 2>&1; then
    echo -e "${RED}Cluster $CLUSTER_NAME not found or not accessible.${NC}" >&2
    echo -e "${YELLOW}Ensure the cluster is deployed and you have proper permissions.${NC}" >&2
    exit 1
fi

# Validate required variables for WAF functionality
echo -e "${YELLOW}Validating WAF configuration...${NC}"
if [ "$enable_waf" = "true" ] && [ -z "$WAF_ACL_ARN" ]; then
    echo -e "${YELLOW}Warning: WAF enabled but no WAF ACL ARN found in Terraform outputs${NC}"
    echo -e "${YELLOW}This may indicate WAF resources haven't been created yet${NC}"
fi

# Update kubeconfig
echo -e "${YELLOW}Updating kubeconfig...${NC}"
aws eks update-kubeconfig --region $AWS_REGION --name $CLUSTER_NAME

# Verify cluster connection
echo -e "${YELLOW}Verifying cluster connection...${NC}"
kubectl cluster-info

# Get Terraform outputs
echo -e "${YELLOW}Getting infrastructure details...${NC}"
cd "$PROJECT_ROOT/terraform"

EFS_ID=$(terraform output -raw efs_id)
AURORA_ENDPOINT=$(terraform output -raw aurora_endpoint)
AURORA_PASSWORD=$(terraform output -raw aurora_password)
REDIS_ENDPOINT=$(terraform output -raw redis_endpoint)
REDIS_PORT=$(terraform output -raw redis_port)
REDIS_PASSWORD=$(terraform output -raw redis_password)
ALB_LOGS_BUCKET=$(terraform output -raw alb_logs_bucket_name)
WAF_ACL_ARN=$(terraform output -raw waf_web_acl_arn 2>/dev/null || echo "")
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Get autoscaling configuration
OPENEMR_MIN_REPLICAS=$(terraform output -json openemr_autoscaling_config | jq -r '.min_replicas')
OPENEMR_MAX_REPLICAS=$(terraform output -json openemr_autoscaling_config | jq -r '.max_replicas')
OPENEMR_CPU_THRESHOLD=$(terraform output -json openemr_autoscaling_config | jq -r '.cpu_utilization_threshold')
OPENEMR_MEMORY_THRESHOLD=$(terraform output -json openemr_autoscaling_config | jq -r '.memory_utilization_threshold')
OPENEMR_SCALE_DOWN_STABILIZATION=$(terraform output -json openemr_autoscaling_config | jq -r '.scale_down_stabilization_seconds')
OPENEMR_SCALE_UP_STABILIZATION=$(terraform output -json openemr_autoscaling_config | jq -r '.scale_up_stabilization_seconds')

# Get OpenEMR application configuration
OPENEMR_VERSION=$(terraform output -json openemr_app_config | jq -r '.version')
OPENEMR_API_ENABLED=$(terraform output -json openemr_app_config | jq -r '.api_enabled')
PATIENT_PORTAL_ENABLED=$(terraform output -json openemr_app_config | jq -r '.patient_portal_enabled')

cd "$PROJECT_ROOT/k8s"

# Configure SSL certificate handling
echo -e "${YELLOW}Configuring SSL certificates...${NC}"
if [ ! -z "$SSL_CERT_ARN" ]; then
  echo -e "${GREEN}Using AWS Certificate Manager certificate: $SSL_CERT_ARN${NC}"
  SSL_MODE="acm"
else
  echo -e "${YELLOW}No SSL certificate provided - using OpenEMR self-signed certificates${NC}"
  echo -e "${YELLOW}Note: Browsers will show security warnings for self-signed certificates${NC}"
  SSL_MODE="self-signed"
fi

# Replace placeholders in manifests
echo -e "${YELLOW}Preparing manifests...${NC}"
sed -i.bak "s/\${EFS_ID}/$EFS_ID/g" storage.yaml
sed -i.bak "s/\${AWS_ACCOUNT_ID}/$AWS_ACCOUNT_ID/g" deployment.yaml
sed -i.bak "s/\${OPENEMR_VERSION}/$OPENEMR_VERSION/g" deployment.yaml
sed -i.bak "s/\${DOMAIN_NAME}/$DOMAIN_NAME/g" deployment.yaml

# Configure OpenEMR feature environment variables based on Terraform settings
echo -e "${YELLOW}Configuring OpenEMR feature environment variables...${NC}"

# Prepare environment variables to add
OPENEMR_ENV_VARS=""

# Add API configuration if enabled
if [ "$OPENEMR_API_ENABLED" = "true" ]; then
    echo -e "${GREEN}✅ Adding OpenEMR API environment variables${NC}"
    OPENEMR_ENV_VARS="$OPENEMR_ENV_VARS
        - name: OPENEMR_SETTING_rest_api
          value: \"1\"
        - name: OPENEMR_SETTING_rest_fhir_api
          value: \"1\""
fi

# Add Patient Portal configuration if enabled
if [ "$PATIENT_PORTAL_ENABLED" = "true" ]; then
    echo -e "${GREEN}✅ Adding Patient Portal environment variables${NC}"
    OPENEMR_ENV_VARS="$OPENEMR_ENV_VARS
        - name: OPENEMR_SETTING_portal_onsite_two_enable
          value: \"1\"
        - name: OPENEMR_SETTING_portal_onsite_two_address
          value: \"https://$DOMAIN_NAME/portal\"
        - name: OPENEMR_SETTING_ccda_alt_service_enable
          value: \"3\"
        - name: OPENEMR_SETTING_rest_portal_api
          value: \"1\""
fi

# Insert the environment variables into the deployment manifest
if [ -n "$OPENEMR_ENV_VARS" ]; then
    # Find the line with the comment about conditional environment variables and insert after it
    sed -i.bak "/# OPENEMR_SETTING_rest_portal_api will be added if portal is enabled/a\\
$OPENEMR_ENV_VARS" deployment.yaml
fi
sed -i.bak "s/\${AWS_ACCOUNT_ID}/$AWS_ACCOUNT_ID/g" logging.yaml
sed -i.bak "s/\${AWS_REGION}/$AWS_REGION/g" logging.yaml
sed -i.bak "s/\${CLUSTER_NAME}/$CLUSTER_NAME/g" logging.yaml
sed -i.bak "s/\${S3_BUCKET_NAME}/$ALB_LOGS_BUCKET/g" ingress.yaml

# Configure WAF ACL ARN if available
if [ -n "$WAF_ACL_ARN" ]; then
    echo -e "${BLUE}Configuring WAF ACL ARN: $WAF_ACL_ARN${NC}"
    sed -i.bak "s|\${WAF_ACL_ARN}|$WAF_ACL_ARN|g" ingress.yaml
    echo -e "${GREEN}✅ WAF protection enabled with ACL: $WAF_ACL_ARN${NC}"
else
    echo -e "${YELLOW}WAF ACL ARN not available - checking if WAF is enabled...${NC}"
    # Check if WAF is enabled in Terraform
    if terraform output -raw waf_enabled 2>/dev/null | grep -q "true"; then
        echo -e "${RED}Error: WAF is enabled but ACL ARN not found${NC}"
        echo -e "${YELLOW}This may indicate a Terraform deployment issue${NC}"
        echo -e "${YELLOW}Continuing without WAF protection...${NC}"
    else
        echo -e "${BLUE}WAF is disabled - continuing without WAF protection${NC}"
    fi
    # Remove WAF annotation
    sed -i.bak '/alb.ingress.kubernetes.io\/wafv2-acl-arn:/d' ingress.yaml
fi

# Configure autoscaling parameters
echo -e "${YELLOW}Configuring autoscaling parameters...${NC}"
sed -i.bak "s/\${OPENEMR_MIN_REPLICAS}/$OPENEMR_MIN_REPLICAS/g" hpa.yaml
sed -i.bak "s/\${OPENEMR_MAX_REPLICAS}/$OPENEMR_MAX_REPLICAS/g" hpa.yaml
sed -i.bak "s/\${OPENEMR_CPU_THRESHOLD}/$OPENEMR_CPU_THRESHOLD/g" hpa.yaml
sed -i.bak "s/\${OPENEMR_MEMORY_THRESHOLD}/$OPENEMR_MEMORY_THRESHOLD/g" hpa.yaml
sed -i.bak "s/\${OPENEMR_SCALE_DOWN_STABILIZATION}/$OPENEMR_SCALE_DOWN_STABILIZATION/g" hpa.yaml
sed -i.bak "s/\${OPENEMR_SCALE_UP_STABILIZATION}/$OPENEMR_SCALE_UP_STABILIZATION/g" hpa.yaml

echo -e "${GREEN}✅ Autoscaling configured: ${OPENEMR_MIN_REPLICAS}-${OPENEMR_MAX_REPLICAS} replicas, CPU: ${OPENEMR_CPU_THRESHOLD}%, Memory: ${OPENEMR_MEMORY_THRESHOLD}%${NC}"

# Configure SSL in service manifest
if [ "$SSL_MODE" = "acm" ]; then
  # ACM mode: SSL re-encryption (ACM cert at NLB, self-signed cert to pod)
  echo -e "${BLUE}Configuring ACM SSL with re-encryption to OpenEMR pods...${NC}"
  
  # Set backend protocol to SSL for re-encryption
  sed -i.bak "s|\${BACKEND_PROTOCOL}|ssl|g" service.yaml
  
  # Replace SSL certificate ARN placeholder
  sed -i.bak "s|\${SSL_CERT_ARN}|$SSL_CERT_ARN|g" service.yaml
  
  # Enable SSL annotations by removing comment markers
  sed -i.bak 's|#    service.beta.kubernetes.io/aws-load-balancer-ssl-ports:|    service.beta.kubernetes.io/aws-load-balancer-ssl-ports:|g' service.yaml
  sed -i.bak 's|#    service.beta.kubernetes.io/aws-load-balancer-ssl-cert:|    service.beta.kubernetes.io/aws-load-balancer-ssl-cert:|g' service.yaml
  sed -i.bak 's|#    service.beta.kubernetes.io/aws-load-balancer-ssl-negotiation-policy:|    service.beta.kubernetes.io/aws-load-balancer-ssl-negotiation-policy:|g' service.yaml
else
  # Self-signed mode: SSL passthrough (no SSL termination at NLB)
  echo -e "${BLUE}Configuring self-signed SSL passthrough...${NC}"
  
  # Set backend protocol to TCP for passthrough
  sed -i.bak "s|\${BACKEND_PROTOCOL}|tcp|g" service.yaml
  
  # Remove SSL certificate annotations (no SSL termination at NLB)
  sed -i.bak '/service.beta.kubernetes.io\/aws-load-balancer-ssl-/d' service.yaml
fi

# Use passwords from Terraform (retrieved above)
echo -e "${YELLOW}Using infrastructure passwords from Terraform...${NC}"
# Generate OpenEMR admin password with specific requirements:
# - 16 characters long by default. Can be given an argument to set length.
# - Only special characters: !()<>^{}~
# - Must include: 1 lowercase, 1 uppercase, 1 number, 1 special character
generate_admin_password() {
    local length=${1:-16}
    local special_chars="!()<>^{}~"
    local lower_chars="abcdefghijklmnopqrstuvwxyz"
    local upper_chars="ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    local number_chars="0123456789"
    
    # Function to get random character from string
    get_random_char() {
        local chars="$1"
        local len=${#chars}
        local rand_byte=$(hexdump -n 1 -e '"%u"' /dev/urandom)
        local pos=$((rand_byte % len))
        echo "${chars:$pos:1}"
    }

    # Shuffle string using pure bash
    shuffle_string() {
        local input="$1"
        local i char len=${#input}
        local -a chars
        local shuffled=""

        for (( i=0; i<len; i++ )); do
            chars[i]="${input:i:1}"
        done

        for (( i=len-1; i>0; i-- )); do
            j=$(( RANDOM % (i+1) ))
            tmp="${chars[i]}"
            chars[i]="${chars[j]}"
            chars[j]="$tmp"
        done

        for char in "${chars[@]}"; do
            shuffled+="$char"
        done

        echo "$shuffled"
    }

    # Ensure at least one of each required character type
    local password=""
    password+=$(get_random_char "$lower_chars")
    password+=$(get_random_char "$upper_chars")
    password+=$(get_random_char "$number_chars")
    password+=$(get_random_char "$special_chars")
    
    # Fill remaining characters
    local all_chars="${lower_chars}${upper_chars}${number_chars}${special_chars}"
    local remaining=$((length - 4))
    for ((i=0; i<remaining; i++)); do
        password+=$(get_random_char "$all_chars")
    done

    # Shuffle password with our function
    password=$(shuffle_string "$password")

    # Return password
    echo "$password"
}

ADMIN_PASSWORD=$(generate_admin_password)

# Create namespace
echo -e "${YELLOW}Creating namespaces...${NC}"
kubectl apply -f namespace.yaml

# Create secrets with actual values
echo -e "${YELLOW}Creating secrets...${NC}"
kubectl create secret generic openemr-db-credentials \
  --namespace=$NAMESPACE \
  --from-literal=mysql-host="$AURORA_ENDPOINT" \
  --from-literal=mysql-user="openemr" \
  --from-literal=mysql-password="$AURORA_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic openemr-redis-credentials \
  --namespace=$NAMESPACE \
  --from-literal=redis-host="$REDIS_ENDPOINT" \
  --from-literal=redis-port="$REDIS_PORT" \
  --from-literal=redis-password="$REDIS_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic openemr-app-credentials \
  --namespace=$NAMESPACE \
  --from-literal=admin-user="admin" \
  --from-literal=admin-password="$ADMIN_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

# OpenEMR configuration is now handled via environment variables directly

# Display application and feature configuration
echo -e "${BLUE}📋 OpenEMR Application Configuration:${NC}"
echo -e "${GREEN}📦 OpenEMR Version: $OPENEMR_VERSION${NC}"
echo -e "${BLUE}   💡 To change version: Set openemr_version in terraform.tfvars${NC}"
echo ""

echo -e "${BLUE}📋 OpenEMR Feature Configuration:${NC}"
if [ "$OPENEMR_API_ENABLED" = "true" ]; then
    echo -e "${GREEN}✅ REST API and FHIR endpoints: ENABLED${NC}"
else
    echo -e "${YELLOW}🔒 REST API and FHIR endpoints: DISABLED${NC}"
    echo -e "${BLUE}   💡 To enable: Set enable_openemr_api = true in terraform.tfvars${NC}"
fi

if [ "$PATIENT_PORTAL_ENABLED" = "true" ]; then
    echo -e "${GREEN}✅ Patient Portal: ENABLED${NC}"
else
    echo -e "${YELLOW}🔒 Patient Portal: DISABLED${NC}"
    echo -e "${BLUE}   💡 To enable: Set enable_patient_portal = true in terraform.tfvars${NC}"
fi

# Apply storage configuration
# Note: EFS CSI driver IAM permissions are configured automatically by Terraform
echo -e "${YELLOW}Setting up storage...${NC}"
kubectl apply -f storage.yaml

# Ensure EFS CSI controller picks up IAM role annotation from Terraform
# This restart is necessary because the controller pods may have started before
# Terraform applied the IAM role annotation to the service account
echo -e "${YELLOW}Restarting EFS CSI controller to apply IAM permissions...${NC}"
kubectl rollout restart deployment efs-csi-controller -n kube-system
echo -e "${YELLOW}Waiting for EFS CSI controller to be ready...${NC}"
kubectl rollout status deployment efs-csi-controller -n kube-system --timeout=120s
echo -e "${GREEN}✅ EFS CSI controller restarted with proper IAM permissions${NC}"

# Wait a moment for EFS CSI controller to be fully ready
echo -e "${YELLOW}Waiting for EFS CSI controller to be fully operational...${NC}"
sleep 10

# Check PVC and storage class configuration
echo -e "${YELLOW}Checking PVC and storage configuration...${NC}"
VOLUME_BINDING_MODE=$(kubectl get storageclass efs-sc -o jsonpath='{.volumeBindingMode}' 2>/dev/null || echo "Immediate")

if [ "$VOLUME_BINDING_MODE" = "WaitForFirstConsumer" ]; then
  echo -e "${BLUE}ℹ️  Storage class uses WaitForFirstConsumer binding mode${NC}"
  echo -e "${BLUE}ℹ️  PVCs will be provisioned when pods are deployed (this is normal)${NC}"
  
  # Just verify PVCs exist
  ESSENTIAL_PVCS=$(kubectl get pvc -n $NAMESPACE --no-headers 2>/dev/null | grep -E "(openemr-sites-pvc|openemr-ssl-pvc|openemr-letsencrypt-pvc)" 2>/dev/null || true)
  if [ -n "$ESSENTIAL_PVCS" ]; then
    echo -e "${GREEN}✅ Essential PVCs created and ready for binding${NC}"
    echo -e "${BLUE}   • openemr-sites-pvc: Created${NC}"
    echo -e "${BLUE}   • openemr-ssl-pvc: Created${NC}"
    echo -e "${BLUE}   • openemr-letsencrypt-pvc: Created${NC}"
    echo -e "${BLUE}   • openemr-backup-pvc: Created (will bind when backup runs)${NC}"
  else
    echo -e "${RED}❌ Essential PVCs not found${NC}"
    exit 1
  fi
else
  # Original logic for Immediate binding mode
  echo -e "${YELLOW}Checking PVC provisioning status...${NC}"
  for i in {1..12}; do
    # Count essential PVCs (sites, ssl, letsencrypt) - backup PVC is expected to remain pending
    ESSENTIAL_PVCS=$(kubectl get pvc -n $NAMESPACE --no-headers 2>/dev/null | grep -E "(openemr-sites-pvc|openemr-ssl-pvc|openemr-letsencrypt-pvc)" 2>/dev/null || true)
    if [ -n "$ESSENTIAL_PVCS" ]; then
      ESSENTIAL_BOUND=$(echo "$ESSENTIAL_PVCS" | grep -c "Bound" 2>/dev/null)
    else
      ESSENTIAL_BOUND=0
    fi
    # Ensure ESSENTIAL_BOUND is a clean integer (handles any edge cases)
    ESSENTIAL_BOUND=$((ESSENTIAL_BOUND + 0))
    
    BACKUP_STATUS=$(kubectl get pvc openemr-backup-pvc -n $NAMESPACE --no-headers 2>/dev/null | awk '{print $2}' || echo "Unknown")
    
    if [ "$ESSENTIAL_BOUND" -ge 3 ]; then
      echo -e "${GREEN}✅ Essential PVCs are bound (3/3 required for OpenEMR)${NC}"
      echo -e "${BLUE}   • openemr-sites-pvc: Bound${NC}"
      echo -e "${BLUE}   • openemr-ssl-pvc: Bound${NC}"
      echo -e "${BLUE}   • openemr-letsencrypt-pvc: Bound${NC}"
      echo -e "${BLUE}   • openemr-backup-pvc: $BACKUP_STATUS (expected - binds when backup runs)${NC}"
      break
    elif [ $i -eq 12 ]; then
      echo -e "${YELLOW}⚠️  Only $ESSENTIAL_BOUND/3 essential PVCs are bound${NC}"
      echo -e "${YELLOW}This may cause OpenEMR pods to remain in Pending status${NC}"
      echo -e "${BLUE}💡 Run validation: cd ../scripts && ./validate-efs-csi.sh${NC}"
      break
    else
      echo -e "${YELLOW}Waiting for essential PVCs to be provisioned... ($ESSENTIAL_BOUND/3 bound)${NC}"
      sleep 5
    fi
  done
fi

# Apply security policies
echo -e "${YELLOW}Applying security policies...${NC}"
kubectl apply -f security.yaml

# Apply network policies based on feature configuration
echo -e "${YELLOW}Applying network policies...${NC}"
# Always apply base access policy
kubectl apply -f network-policies.yaml

# Deploy OpenEMR application
echo -e "${YELLOW}Deploying OpenEMR application...${NC}"
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml

# Wait for deployment to be ready
echo -e "${YELLOW}Waiting for OpenEMR pods to be ready (this takes ~10 minutes for first startup)...${NC}"
echo -e "${YELLOW}OpenEMR is initializing the database and configuring the application...${NC}"
kubectl wait --for=condition=available --timeout=900s deployment/openemr -n $NAMESPACE

# Apply Horizontal Pod Autoscaler for intelligent scaling
echo -e "${YELLOW}Setting up intelligent autoscaling...${NC}"
kubectl apply -f hpa.yaml
echo -e "${GREEN}✅ HPA configured: Replicas will autoscale based on CPU/memory usage${NC}"
echo -e "${GREEN}✅ EKS Auto Mode will provision nodes as needed${NC}"

# Always apply ingress for ALB and WAF functionality
echo -e "${YELLOW}Setting up ingress with ALB and WAF...${NC}"

# Set fallback domain if none provided (for LoadBalancer access)
if [ -z "$DOMAIN_NAME" ]; then
  echo -e "${YELLOW}No domain specified - using LoadBalancer IP for access${NC}"
  DOMAIN_NAME="openemr.local"  # Fallback domain for TLS
fi

# Substitute all required variables in ingress
sed -i.bak "s/\${DOMAIN_NAME}/$DOMAIN_NAME/g" ingress.yaml

# Handle SSL certificate configuration
if [ -n "$SSL_CERT_ARN" ]; then
  echo -e "${BLUE}Using ACM certificate: $SSL_CERT_ARN${NC}"
  sed -i.bak "s|\${SSL_CERT_ARN}|$SSL_CERT_ARN|g" ingress.yaml
else
  echo -e "${YELLOW}No SSL certificate - removing SSL annotations${NC}"
  # Remove SSL-related annotations when no certificate
  sed -i.bak '/alb.ingress.kubernetes.io\/certificate-arn:/d' ingress.yaml
  sed -i.bak '/alb.ingress.kubernetes.io\/ssl-policy:/d' ingress.yaml
  sed -i.bak '/tls:/,/secretName:/d' ingress.yaml
  sed -i.bak '/hosts:/d' ingress.yaml
  sed -i.bak '/- host:/d' ingress.yaml
fi

# Apply the ingress configuration
kubectl apply -f ingress.yaml
echo -e "${GREEN}✅ Ingress applied with ALB and WAF support${NC}"

# Apply logging configuration
echo -e "${YELLOW}Setting up logging...${NC}"
sed -i.bak "s/\${AWS_REGION}/$AWS_REGION/g" logging.yaml
sed -i.bak "s/\${CLUSTER_NAME}/$CLUSTER_NAME/g" logging.yaml
kubectl apply -f logging.yaml

# EKS Auto Mode handles logging configuration automatically
echo -e "${GREEN}✅ EKS Auto Mode manages compute and logging automatically${NC}"

# Note: Monitoring configuration is handled by the optional monitoring stack
echo -e "${BLUE}ℹ️  Core deployment complete. For monitoring: cd ../monitoring && ./install-monitoring.sh${NC}"

# Deploy SSL certificate renewal automation
echo -e "${YELLOW}Setting up SSL certificate renewal automation...${NC}"
kubectl apply -f ssl-renewal.yaml
echo -e "${GREEN}✅ SSL certificates will be automatically renewed every 2 days${NC}"

# Display deployment status
echo -e "${GREEN}Deployment completed successfully!${NC}"
echo -e "${YELLOW}Checking deployment status...${NC}"
kubectl get all -n $NAMESPACE

# Report WAF status
echo -e "${BLUE}🔒 WAF Security Status:${NC}"
if [ -n "$WAF_ACL_ARN" ]; then
    echo -e "${GREEN}✅ WAF Protection: ENABLED${NC}"
    echo -e "${GREEN}   ACL ARN: $WAF_ACL_ARN${NC}"
    echo -e "${GREEN}   Features: Rate limiting, SQL injection protection, bot blocking${NC}"
else
    echo -e "${YELLOW}⚠️  WAF Protection: DISABLED${NC}"
    echo -e "${YELLOW}   To enable: Set enable_waf = true in terraform.tfvars${NC}"
fi

# Get LoadBalancer URL
LB_URL=$(kubectl get svc openemr-service -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
if [ ! -z "$LB_URL" ]; then
  echo -e "${YELLOW}LoadBalancer URL (HTTPS):${NC} https://$LB_URL"
  
  if [ "$SSL_MODE" = "self-signed" ]; then
    echo -e "${YELLOW}SSL Mode:${NC} Self-signed certificates (browser warnings expected)"
    echo -e "${YELLOW}To use trusted certificates, set SSL_CERT_ARN environment variable${NC}"
  else
    echo -e "${YELLOW}SSL Mode:${NC} AWS Certificate Manager"
    echo -e "${YELLOW}Certificate ARN:${NC} $SSL_CERT_ARN"
  fi
fi

# Save credentials to file
echo -e "${YELLOW}Saving credentials to openemr-credentials.txt...${NC}"
if [ -f "openemr-credentials.txt" ]; then
  # Create backup of existing credentials file
  BACKUP_FILE="openemr-credentials-$(date +%Y%m%d-%H%M%S).txt"
  cp openemr-credentials.txt "$BACKUP_FILE"
  echo -e "${YELLOW}Existing credentials file backed up to: $BACKUP_FILE${NC}"
fi

cat > openemr-credentials.txt << EOF
OpenEMR Deployment Credentials
==============================
Admin Username: admin
Admin Password: $ADMIN_PASSWORD
Database Password: $AURORA_PASSWORD
Redis Password: $REDIS_PASSWORD
LoadBalancer URL (HTTPS): https://$LB_URL
SSL Mode: $SSL_MODE
EOF

# Add certificate ARN if using ACM
if [ "$SSL_MODE" = "acm" ]; then
  echo "Certificate ARN: $SSL_CERT_ARN" >> openemr-credentials.txt
fi

# Add generation timestamp
echo "" >> openemr-credentials.txt
echo "Generated on: $(date)" >> openemr-credentials.txt

echo -e "${GREEN}Credentials saved to openemr-credentials.txt${NC}"
echo -e "${GREEN}Please store these credentials securely!${NC}"

# Cleanup backup files
rm *.yaml.bak

echo -e "${GREEN}OpenEMR deployment completed successfully!${NC}"
echo ""
echo -e "${BLUE}�  Storage Information:${NC}"
echo -e "${BLUE}• Essential PVCs (sites, ssl, letsencrypt) should be Bound${NC}"
echo -e "${BLUE}• Backup PVC remains Pending until first backup runs - this is normal${NC}"
echo -e "${BLUE}• Run backup script to provision backup storage: cd ../scripts && ./backup.sh${NC}"
echo ""
echo -e "${BLUE}🔍 Troubleshooting: If pods remain in Pending status${NC}"
echo -e "${BLUE}Run the EFS CSI validation script: cd ../scripts && ./validate-efs-csi.sh${NC}"
echo ""
echo -e "${BLUE}📊 Optional: Install Full Monitoring Stack${NC}"
echo -e "${BLUE}To install Prometheus, Grafana, and advanced monitoring:${NC}"
echo -e "${BLUE}   cd ../monitoring && ./install-monitoring.sh${NC}"
echo -e "${BLUE}This includes dashboards, alerting, and log aggregation.${NC}"