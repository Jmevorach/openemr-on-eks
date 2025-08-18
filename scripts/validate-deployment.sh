#!/bin/bash

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

echo -e "${BLUE}🔍 OpenEMR Deployment Validation${NC}"
echo -e "${BLUE}================================${NC}"

# Function to check command availability
check_command() {
    if command -v $1 >/dev/null 2>&1; then
        echo -e "${GREEN}✅ $1 is installed${NC}"
        return 0
    else
        echo -e "${RED}❌ $1 is not installed${NC}"
        return 1
    fi
}

# Function to check AWS credentials
check_aws_credentials() {
    echo -e "${BLUE}Checking AWS credential sources...${NC}"
    
    # Check if credentials work first
    if aws sts get-caller-identity >/dev/null 2>&1; then
        ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        USER_ARN=$(aws sts get-caller-identity --query Arn --output text)
        echo -e "${GREEN}✅ AWS credentials valid${NC}"
        echo -e "${GREEN}   Account ID: $ACCOUNT_ID${NC}"
        echo -e "${GREEN}   User/Role: $USER_ARN${NC}"
        
        # Detect credential source
        detect_credential_source
        return 0
    else
        echo -e "${RED}❌ AWS credentials invalid or not configured${NC}"
        echo -e "${YELLOW}💡 Configure credentials using one of these methods:${NC}"
        echo -e "${YELLOW}   • aws configure${NC}"
        echo -e "${YELLOW}   • AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY environment variables${NC}"
        echo -e "${YELLOW}   • IAM instance profile (if running on EC2)${NC}"
        echo -e "${YELLOW}   • AWS SSO: aws sso login${NC}"
        return 1
    fi
}

# Function to detect AWS credential source
detect_credential_source() {
    local cred_sources=()
    
    # Check environment variables
    if [ ! -z "$AWS_ACCESS_KEY_ID" ] && [ ! -z "$AWS_SECRET_ACCESS_KEY" ]; then
        cred_sources+=("Environment variables (AWS_ACCESS_KEY_ID)")
        echo -e "${BLUE}   📍 Source: Environment variables${NC}"
    fi
    
    # Check AWS credentials file
    AWS_CREDS_FILE="${AWS_SHARED_CREDENTIALS_FILE:-$HOME/.aws/credentials}"
    if [ -f "$AWS_CREDS_FILE" ]; then
        cred_sources+=("Credentials file ($AWS_CREDS_FILE)")
        echo -e "${BLUE}   📍 Source: Credentials file found at $AWS_CREDS_FILE${NC}"
        
        # Check which profiles are available
        if command -v grep >/dev/null 2>&1; then
            PROFILES=$(grep -E '^\[.*\]' "$AWS_CREDS_FILE" | sed 's/\[//g' | sed 's/\]//g' | tr '\n' ', ' | sed 's/, $//')
            if [ ! -z "$PROFILES" ]; then
                echo -e "${BLUE}   📋 Available profiles: $PROFILES${NC}"
            fi
        fi
        
        # Check current profile
        CURRENT_PROFILE="${AWS_PROFILE:-default}"
        echo -e "${BLUE}   🎯 Current profile: $CURRENT_PROFILE${NC}"
    fi
    
    # Check AWS config file
    AWS_CONFIG_FILE="${AWS_CONFIG_FILE:-$HOME/.aws/config}"
    if [ -f "$AWS_CONFIG_FILE" ]; then
        echo -e "${BLUE}   📍 Config file found at $AWS_CONFIG_FILE${NC}"
        
        # Check for SSO configuration
        if grep -q "sso_" "$AWS_CONFIG_FILE" 2>/dev/null; then
            cred_sources+=("AWS SSO configuration")
            echo -e "${BLUE}   🔐 SSO configuration detected${NC}"
        fi
        
        # Check for role assumption
        if grep -q "role_arn" "$AWS_CONFIG_FILE" 2>/dev/null; then
            cred_sources+=("IAM role assumption")
            echo -e "${BLUE}   👤 Role assumption configured${NC}"
        fi
    fi
    
    # Check for instance profile (if running on EC2)
    if curl -s --max-time 2 http://169.254.169.254/latest/meta-data/iam/security-credentials/ >/dev/null 2>&1; then
        cred_sources+=("EC2 instance profile")
        echo -e "${BLUE}   🖥️  EC2 instance profile detected${NC}"
    fi
    
    # Check for ECS task role
    if [ ! -z "$AWS_CONTAINER_CREDENTIALS_RELATIVE_URI" ]; then
        cred_sources+=("ECS task role")
        echo -e "${BLUE}   📦 ECS task role detected${NC}"
    fi
    
    # Check current region
    CURRENT_REGION=$(aws configure get region 2>/dev/null || echo "not set")
    echo -e "${BLUE}   🌍 Current region: $CURRENT_REGION${NC}"
    
    if [ "$CURRENT_REGION" = "not set" ]; then
        echo -e "${YELLOW}   ⚠️  AWS region not configured${NC}"
        echo -e "${YELLOW}   💡 Set region: aws configure set region $AWS_REGION${NC}"
    elif [ "$CURRENT_REGION" != "$AWS_REGION" ]; then
        echo -e "${YELLOW}   ⚠️  Current region ($CURRENT_REGION) differs from deployment region ($AWS_REGION)${NC}"
        echo -e "${YELLOW}   💡 Consider setting region: aws configure set region $AWS_REGION${NC}"
    fi
    
    # Summary of credential sources
    if [ ${#cred_sources[@]} -eq 0 ]; then
        echo -e "${YELLOW}   ❓ Credential source unclear${NC}"
    else
        echo -e "${GREEN}   ✅ Credential sources detected: ${#cred_sources[@]}${NC}"
    fi
}

# Function to check cluster accessibility
check_cluster_access() {
    if aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION >/dev/null 2>&1; then
        echo -e "${GREEN}✅ EKS cluster '$CLUSTER_NAME' is accessible${NC}"
        
        # Check if kubectl can connect
        if kubectl get nodes >/dev/null 2>&1; then
            echo -e "${GREEN}✅ kubectl can connect to cluster (EKS Auto Mode)${NC}"
            echo -e "${GREEN}💡 Auto Mode manages compute automatically - no nodes to count${NC}"
            return 0
        else
            echo -e "${YELLOW}⚠️  kubectl cannot connect to cluster${NC}"
            echo -e "${YELLOW}💡 Your IP may have changed. Run: $SCRIPT_DIR/cluster-security-manager.sh check-ip${NC}"
            return 1
        fi
    else
        echo -e "${BLUE}ℹ️  EKS cluster '$CLUSTER_NAME' not found${NC}"
        echo -e "${BLUE}💡 This is expected for first-time deployments${NC}"
        return 2  # Special return code for first-time deployment
    fi
}

# Function to check Terraform state
check_terraform_state() {
    # Detect script location and set project root
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ "$SCRIPT_DIR" == */scripts ]]; then
        PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
    else
        PROJECT_ROOT="$SCRIPT_DIR"
    fi
    
    if [ -f "$PROJECT_ROOT/terraform/terraform.tfstate" ]; then
        echo -e "${GREEN}✅ Terraform state file exists${NC}"
        
        # Check if infrastructure is deployed
        cd "$PROJECT_ROOT/terraform"
        if terraform show >/dev/null 2>&1; then
            RESOURCES=$(terraform show -json | jq -r '.values.root_module.resources | length' 2>/dev/null || echo "0")
            if [ "$RESOURCES" -gt 0 ]; then
                echo -e "${GREEN}✅ Terraform infrastructure deployed ($RESOURCES resources)${NC}"
                cd "$SCRIPT_DIR"
                return 0
            else
                echo -e "${BLUE}ℹ️  Terraform state exists but no resources deployed${NC}"
                echo -e "${BLUE}💡 This indicates a clean slate for deployment${NC}"
                cd "$SCRIPT_DIR"
                return 2  # Special return code for clean slate
            fi
        else
            echo -e "${YELLOW}⚠️  Terraform state exists but may be corrupted${NC}"
            cd "$SCRIPT_DIR"
            return 1
        fi
    else
        echo -e "${BLUE}ℹ️  Terraform state file not found${NC}"
        echo -e "${BLUE}💡 This is expected for first-time deployments${NC}"
        echo -e "${BLUE}📋 Next step: cd $PROJECT_ROOT/terraform && terraform init && terraform apply${NC}"
        return 2  # Special return code for first-time deployment
    fi
}

# Function to check required resources
check_required_resources() {
    echo -e "${BLUE}Checking AWS resources...${NC}"
    
    local resources_found=0
    local total_resources=4
    
    # Check VPC
    VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=${CLUSTER_NAME}-vpc" --query 'Vpcs[0].VpcId' --output text 2>/dev/null)
    if [ "$VPC_ID" != "None" ] && [ "$VPC_ID" != "" ]; then
        echo -e "${GREEN}✅ VPC exists: $VPC_ID${NC}"
        ((resources_found++))
    else
        echo -e "${BLUE}ℹ️  VPC not found${NC}"
        echo -e "${BLUE}💡 This is expected for first-time deployments${NC}"
    fi
    
    # Check RDS cluster
    RDS_CLUSTER=$(aws rds describe-db-clusters --query "DBClusters[?contains(DBClusterIdentifier, '${CLUSTER_NAME}')].DBClusterIdentifier" --output text 2>/dev/null)
    if [ "$RDS_CLUSTER" != "" ]; then
        echo -e "${GREEN}✅ RDS Aurora cluster exists: $RDS_CLUSTER${NC}"
        ((resources_found++))
    else
        echo -e "${BLUE}ℹ️  RDS Aurora cluster not found${NC}"
        echo -e "${BLUE}💡 This is expected for first-time deployments${NC}"
    fi
    
    # Check ElastiCache
    REDIS_CLUSTER=$(aws elasticache describe-serverless-caches --query "ServerlessCaches[?contains(ServerlessCacheName, '${CLUSTER_NAME}')].ServerlessCacheName" --output text 2>/dev/null)
    if [ "$REDIS_CLUSTER" != "" ]; then
        echo -e "${GREEN}✅ ElastiCache Valkey cluster exists: $REDIS_CLUSTER${NC}"
        ((resources_found++))
    else
        echo -e "${BLUE}ℹ️  ElastiCache Valkey cluster not found${NC}"
        echo -e "${BLUE}💡 This is expected for first-time deployments${NC}"
    fi
    
    # Check EFS
    EFS_ID=$(aws efs describe-file-systems --query "FileSystems[?contains(Name, '${CLUSTER_NAME}')].FileSystemId" --output text 2>/dev/null)
    if [ "$EFS_ID" != "" ]; then
        echo -e "${GREEN}✅ EFS file system exists: $EFS_ID${NC}"
        ((resources_found++))
    else
        echo -e "${BLUE}ℹ️  EFS file system not found${NC}"
        echo -e "${BLUE}💡 This is expected for first-time deployments${NC}"
    fi
    
    # Return special code for first-time deployment
    if [ $resources_found -eq 0 ]; then
        return 2  # Special return code for first-time deployment
    elif [ $resources_found -eq $total_resources ]; then
        return 0  # All resources found
    else
        return 1  # Some resources found, some missing (potential issue)
    fi
}

# Function to check Kubernetes resources
check_k8s_resources() {
    echo -e "${BLUE}Checking Kubernetes resources...${NC}"
    
    local resources_found=0
    local total_resources=2
    
    # Check namespace
    if kubectl get namespace $NAMESPACE >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Namespace '$NAMESPACE' exists${NC}"
        ((resources_found++))
    else
        echo -e "${YELLOW}⚠️  Namespace '$NAMESPACE' not found${NC}"
        echo -e "${YELLOW}💡 Will be created during deployment${NC}"
    fi
    
    # Check if OpenEMR is already deployed
    if kubectl get deployment openemr -n $NAMESPACE >/dev/null 2>&1; then
        REPLICAS=$(kubectl get deployment openemr -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        echo -e "${YELLOW}⚠️  OpenEMR deployment already exists ($REPLICAS ready replicas)${NC}"
        echo -e "${YELLOW}💡 Deployment will update existing resources${NC}"
        ((resources_found++))
    else
        echo -e "${GREEN}✅ OpenEMR not yet deployed (clean deployment)${NC}"
    fi
    
    # Check EKS Auto Mode
    echo -e "${GREEN}✅ EKS Auto Mode handles compute automatically${NC}"
    echo -e "${GREEN}💡 No Karpenter needed - Auto Mode manages all compute${NC}"
    
    # Return special code for first-time deployment
    if [ $resources_found -eq 0 ]; then
        return 2  # Special return code for first-time deployment
    elif [ $resources_found -eq $total_resources ]; then
        return 0  # All resources found
    else
        return 1  # Some resources found, some missing (potential issue)
    fi
}

# Function to check security configuration
check_security_config() {
    echo -e "${BLUE}Checking security configuration...${NC}"
    
    # Check if cluster exists first
    if ! aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION >/dev/null 2>&1; then
        echo -e "${BLUE}ℹ️  EKS cluster not found - security configuration will be applied during deployment${NC}"
        echo -e "${BLUE}📋 Planned deployment features:${NC}"
        echo -e "${BLUE}   • OpenEMR 7.0.3 with HTTPS-only access (port 443)${NC}"
        echo -e "${BLUE}   • EKS Auto Mode for managed EC2 compute${NC}"
        echo -e "${BLUE}   • Aurora Serverless V2 MySQL database${NC}"
        echo -e "${BLUE}   • Valkey Serverless cache (Redis-compatible)${NC}"
        echo -e "${BLUE}   • IP-restricted cluster endpoint access${NC}"
        echo -e "${BLUE}   • Private subnet deployment${NC}"
        echo -e "${BLUE}   • 6 dedicated KMS keys (EKS, EFS, RDS, ElastiCache, S3, CloudWatch)${NC}"
        echo -e "${BLUE}   • Network policies and Pod Security Standards${NC}"
        return 0
    fi
    
    # Check cluster endpoint access
    PUBLIC_ACCESS=$(aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION --query 'cluster.resourcesVpcConfig.endpointPublicAccess' --output text 2>/dev/null)
    PRIVATE_ACCESS=$(aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION --query 'cluster.resourcesVpcConfig.endpointPrivateAccess' --output text 2>/dev/null)
    
    if [ "$PUBLIC_ACCESS" = "True" ]; then
        ALLOWED_CIDRS=$(aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION --query 'cluster.resourcesVpcConfig.publicAccessCidrs' --output text 2>/dev/null)
        echo -e "${YELLOW}⚠️  Public access enabled for: $ALLOWED_CIDRS${NC}"
        echo -e "${YELLOW}💡 Consider disabling after deployment: $SCRIPT_DIR/cluster-security-manager.sh disable${NC}"
    else
        echo -e "${GREEN}✅ Public access disabled (secure)${NC}"
    fi
    
    if [ "$PRIVATE_ACCESS" = "True" ]; then
        echo -e "${GREEN}✅ Private access enabled${NC}"
    else
        echo -e "${RED}❌ Private access disabled (not recommended)${NC}"
    fi
    
    # Check encryption
    ENCRYPTION_CONFIG=$(aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION --query 'cluster.encryptionConfig' --output text 2>/dev/null)
    if [ "$ENCRYPTION_CONFIG" != "None" ] && [ "$ENCRYPTION_CONFIG" != "" ]; then
        echo -e "${GREEN}✅ EKS secrets encryption enabled${NC}"
    else
        echo -e "${RED}❌ EKS secrets encryption not configured${NC}"
    fi
    
    return 0
}

# Function to provide deployment recommendations
provide_recommendations() {
    echo -e "${BLUE}📋 Deployment Recommendations${NC}"
    echo -e "${BLUE}=============================${NC}"
    
    # Only check IP changes if cluster exists
    if aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION >/dev/null 2>&1; then
        # Check current IP
        CURRENT_IP=$(curl -s https://checkip.amazonaws.com 2>/dev/null || echo "unknown")
        ALLOWED_IP=$(aws eks describe-cluster --name $CLUSTER_NAME --region $AWS_REGION --query 'cluster.resourcesVpcConfig.publicAccessCidrs[0]' --output text 2>/dev/null | cut -d'/' -f1)
        
        if [ "$CURRENT_IP" != "$ALLOWED_IP" ] && [ "$CURRENT_IP" != "unknown" ] && [ "$ALLOWED_IP" != "None" ] && [ "$ALLOWED_IP" != "" ]; then
            echo -e "${YELLOW}💡 Your IP has changed since cluster creation${NC}"
            echo -e "${YELLOW}   Current IP: $CURRENT_IP${NC}"
            echo -e "${YELLOW}   Allowed IP: $ALLOWED_IP${NC}"
            echo -e "${YELLOW}   Run: $SCRIPT_DIR/cluster-security-manager.sh enable${NC}"
            echo ""
        fi
    fi
    
    # Security recommendations
    echo -e "${GREEN}🔒 Security Best Practices:${NC}"
    echo -e "   • HTTPS-only access (port 443) - HTTP traffic is refused"
    echo -e "   • Disable public access after deployment"
    echo -e "   • Use strong passwords for all services"
    echo -e "   • Enable AWS WAF for production"
    echo -e "   • Regularly update container images"
    echo -e "   • Monitor audit logs for compliance"
    echo ""
    
    # Cost optimization
    echo -e "${GREEN}💰 Cost Optimization:${NC}"
    echo -e "   • Aurora Serverless V2 scales automatically"
    echo -e "   • EKS Auto Mode: EC2 costs + management fee for full automation"
    echo -e "   • Valkey Serverless provides cost-effective caching"
    echo -e "   • Monitor usage with CloudWatch dashboards"
    echo -e "   • Set up cost alerts and budgets"
    echo ""
    
    # Monitoring
    echo -e "${GREEN}📊 Monitoring Setup:${NC}"
    echo -e "   • CloudWatch logging with Fluent Bit (included in OpenEMR deployment)"
    echo -e "   • Basic deployment: CloudWatch logs only"
    echo -e "   • Optional: Enhanced monitoring stack: cd $PROJECT_ROOT/monitoring && ./install-monitoring.sh"
    echo -e "   • Enhanced stack includes:"
    echo -e "     - Prometheus v75.18.1 (metrics & alerting)"
    echo -e "     - Grafana (dashboards with auto-discovery)"
    echo -e "     - Loki v3.5.3 (log aggregation)"
    echo -e "     - Jaeger v3.4.1 (distributed tracing)"
    echo -e "     - AlertManager (Slack integration support)"
    echo -e "     - OpenEMR-specific monitoring (ServiceMonitor, PrometheusRule)"
    echo -e "   • Configure alerting for critical issues"
    echo -e "   • Regular backup testing"
    echo ""
}

# Main validation flow
main() {
    local errors=0
    local first_time_deployment=false
    
    echo -e "${BLUE}1. Checking prerequisites...${NC}"
    check_command "kubectl" || ((errors++))
    check_command "aws" || ((errors++))
    check_command "helm" || ((errors++))
    check_command "jq" || echo -e "${YELLOW}⚠️  jq not installed (optional but recommended)${NC}"
    echo ""
    
    echo -e "${BLUE}2. Checking AWS credentials...${NC}"
    check_aws_credentials || ((errors++))
    echo ""
    
    echo -e "${BLUE}3. Checking Terraform state...${NC}"
    check_terraform_state
    local terraform_check_result=$?
    if [ "$terraform_check_result" -eq 2 ]; then
        first_time_deployment=true
        echo -e "${BLUE}💡 This is normal for first-time deployments${NC}"
    elif [ "$terraform_check_result" -eq 1 ]; then
        ((errors++))
    fi
    echo ""
    
    echo -e "${BLUE}4. Checking cluster access...${NC}"
    check_cluster_access
    local cluster_access_check_result=$?
    if [ "$cluster_access_check_result" -eq 2 ]; then
        first_time_deployment=true
        echo -e "${BLUE}💡 This is normal for first-time deployments${NC}"
    elif [ "$cluster_access_check_result" -eq 1 ]; then
        ((errors++))
    fi
    echo ""
    
    echo -e "${BLUE}5. Checking AWS resources...${NC}"
    check_required_resources
    local aws_resources_check_result=$?
    if [ "$aws_resources_check_result" -eq 2 ]; then
        first_time_deployment=true
        echo -e "${BLUE}💡 This is normal for first-time deployments${NC}"
    elif [ "$aws_resources_check_result" -eq 1 ]; then
        ((errors++))
    fi
    echo ""
    
    echo -e "${BLUE}6. Checking Kubernetes resources...${NC}"
    check_k8s_resources
    local k8s_resources_check_result=$?
    if [ "$k8s_resources_check_result" -eq 2 ]; then
        first_time_deployment=true
        echo -e "${BLUE}💡 This is normal for first-time deployments${NC}"
    elif [ "$k8s_resources_check_result" -eq 1 ]; then
        ((errors++))
    fi
    echo ""
    
    echo -e "${BLUE}7. Checking security configuration...${NC}"
    check_security_config
    echo ""
    
    # Summary
    if [ "$first_time_deployment" = true ] && [ $errors -eq 0 ]; then
        echo -e "${GREEN}🎉 First-time deployment validation completed!${NC}"
        echo -e "${GREEN}✅ Prerequisites and AWS credentials are ready${NC}"
        echo -e "${BLUE}📋 You're all set for your first deployment!${NC}"
        echo ""
        echo -e "${BLUE}Next steps for first-time deployment:${NC}"
        echo -e "${BLUE}   1. cd $PROJECT_ROOT/terraform${NC}"
        echo -e "${BLUE}   2. terraform init${NC}"
        echo -e "${BLUE}   3. terraform plan${NC}"
        echo -e "${BLUE}   4. terraform apply${NC}"
        echo -e "${BLUE}   5. cd $PROJECT_ROOT/k8s${NC}"
        echo -e "${BLUE}   6. ./deploy.sh${NC}"
        echo ""
        echo -e "${YELLOW}⏱️  Expected deployment time: 25-35 minutes total${NC}"
        echo -e "${YELLOW}   • Infrastructure (Terraform): 15-20 minutes${NC}"
        echo -e "${YELLOW}   • Application (Kubernetes): 10-15 minutes${NC}"
        echo ""
    elif [ $errors -eq 0 ]; then
        echo -e "${GREEN}🎉 Validation completed successfully!${NC}"
        echo -e "${GREEN}✅ Ready to deploy OpenEMR${NC}"
        echo ""
        echo -e "${BLUE}Next steps:${NC}"
        echo -e "   1. cd $PROJECT_ROOT/k8s"
        echo -e "   2. ./deploy.sh"
        echo ""
    else
        echo -e "${RED}❌ Validation failed with $errors error(s)${NC}"
        echo -e "${RED}Please fix the issues above before deploying${NC}"
        echo ""
    fi
    
    provide_recommendations
    
    return $errors
}

# Run main function
main "$@"