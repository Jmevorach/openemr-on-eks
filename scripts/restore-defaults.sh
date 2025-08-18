#!/bin/bash

# OpenEMR Deployment Files Default State Restoration Script
# This script restores all deployment files to their default state for clean git tracking

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Get the script's directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Help function
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Restore OpenEMR deployment files to their default state"
    echo ""
    echo "Options:"
    echo "  --force         Skip confirmation prompts"
    echo "  --backup        Create backup before restoration"
    echo "  --help          Show this help message"
    echo ""
    echo "What this script does:"
    echo "  • Removes all .bak files created by deployment scripts"
    echo "  • Restores deployment.yaml to default template state"
    echo "  • Restores service.yaml to default template state"
    echo "  • Restores hpa.yaml to default template state"
    echo "  • Restores storage.yaml to default template state"
    echo "  • Restores ingress.yaml to default template state"
    echo "  • Restores logging.yaml to default template state"
    echo "  • Removes generated credentials files"
    echo "  • Cleans up temporary deployment files"
    echo ""
    echo "⚠️  IMPORTANT WARNING FOR DEVELOPERS:"
    echo "  • This script will ERASE any structural changes to YAML files"
    echo "  • If you're modifying file structure/content (not just values),"
    echo "  • your changes will be LOST and restored to git HEAD state"
    echo "  • Only use this script for cleaning up deployment artifacts"
    echo "  • NOT for cleaning up during active development work"
    echo ""
    echo "Files preserved:"
    echo "  • terraform.tfvars (your configuration)"
    echo "  • All infrastructure state"
    echo "  • All documentation"
    echo "  • All scripts"
    echo ""
    echo "Use this script to:"
    echo "  • Clean up after deployments for git tracking"
    echo "  • Reset files before making configuration changes"
    echo "  • Prepare for fresh deployments"
    exit 0
}

# Function to create backup
create_backup() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="$PROJECT_ROOT/backups/restore_backup_$timestamp"
    
    echo -e "${YELLOW}Creating backup in $backup_dir...${NC}"
    mkdir -p "$backup_dir"
    
    # Backup k8s directory
    cp -r "$PROJECT_ROOT/k8s" "$backup_dir/"
    
    echo -e "${GREEN}✅ Backup created successfully${NC}"
}

# Function to restore deployment.yaml to default state
restore_deployment_yaml() {
    echo -e "${YELLOW}Restoring deployment.yaml to default state...${NC}"
    
    # Try to restore from git first
    cd "$PROJECT_ROOT"
    if git checkout HEAD -- k8s/deployment.yaml 2>/dev/null; then
        echo -e "${GREEN}✅ deployment.yaml restored from git${NC}"
        return
    fi
    
    # Fallback: create from template
    cat > "$PROJECT_ROOT/k8s/deployment.yaml" << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: openemr
  namespace: openemr
  labels:
    app: openemr
    version: v1
spec:
  # replicas managed by HPA - see hpa.yaml
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  selector:
    matchLabels:
      app: openemr
  template:
    metadata:
      labels:
        app: openemr
        version: v1
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "9090"
    spec:
      securityContext:
        runAsNonRoot: false
        fsGroup: 0
        seccompProfile:
          type: RuntimeDefault
      serviceAccountName: openemr-sa
      containers:
      - name: openemr
        image: openemr/openemr:${OPENEMR_VERSION}
        imagePullPolicy: IfNotPresent
        securityContext:
          allowPrivilegeEscalation: true
          readOnlyRootFilesystem: false
          runAsUser: 0
          runAsGroup: 0
          capabilities:
            drop:
            - ALL
            add:
            - NET_BIND_SERVICE
            - CHOWN
            - SETUID
            - SETGID
            - FOWNER
            - DAC_OVERRIDE
        ports:
        - containerPort: 80
          name: http
          protocol: TCP
        - containerPort: 443
          name: https
          protocol: TCP
        workingDir: /var/www/localhost/htdocs/openemr
        command: ["/bin/sh", "-c"]
        args:
        - |          
          # Download AWS root CA certificates for secure connections
          echo "=== Downloading SSL certificates ==="
          curl --cacert /swarm-pieces/ssl/certs/ca-certificates.crt -o /root/certs/redis/redis-ca --create-dirs https://www.amazontrust.com/repository/AmazonRootCA1.pem && \
          chown apache /root/certs/redis/redis-ca && \
          curl --cacert /swarm-pieces/ssl/certs/ca-certificates.crt -o /root/certs/mysql/server/mysql-ca --create-dirs https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem && \
          chown apache /root/certs/mysql/server/mysql-ca && \
          
          # Setting up crontab for certificate renewal
          echo "1 23 * * * httpd -k graceful" >> /etc/crontabs/root && \
          
          echo "=== Setting up OpenEMR script ==="
          chmod +x ./openemr.sh && \
          
          echo "=== Starting OpenEMR initialization ==="
          ./openemr.sh && \
          
          echo "=== OpenEMR Ready ==="
          # Keep the container running
          tail -f /dev/null
        env:
        - name: MYSQL_HOST
          valueFrom:
            secretKeyRef:
              name: openemr-db-credentials
              key: mysql-host
        - name: MYSQL_ROOT_USER
          valueFrom:
            secretKeyRef:
              name: openemr-db-credentials
              key: mysql-user
        - name: MYSQL_ROOT_PASS
          valueFrom:
            secretKeyRef:
              name: openemr-db-credentials
              key: mysql-password
        - name: MYSQL_USER
          valueFrom:
            secretKeyRef:
              name: openemr-db-credentials
              key: mysql-user
        - name: MYSQL_PASS
          valueFrom:
            secretKeyRef:
              name: openemr-db-credentials
              key: mysql-password
        - name: MYSQL_PORT
          value: "3306"
        - name: REDIS_SERVER
          valueFrom:
            secretKeyRef:
              name: openemr-redis-credentials
              key: redis-host
        - name: REDIS_PORT
          valueFrom:
            secretKeyRef:
              name: openemr-redis-credentials
              key: redis-port
        - name: REDIS_USERNAME
          value: "openemr"
        - name: REDIS_PASSWORD
          valueFrom:
            secretKeyRef:
              name: openemr-redis-credentials
              key: redis-password
        - name: REDIS_TLS
          value: "yes"
        - name: OE_USER
          valueFrom:
            secretKeyRef:
              name: openemr-app-credentials
              key: admin-user
        - name: OE_PASS
          valueFrom:
            secretKeyRef:
              name: openemr-app-credentials
              key: admin-password
        - name: SWARM_MODE
          value: "yes"
        # OpenEMR API Configuration (conditionally set by deploy script)
        # OPENEMR_SETTING_rest_api will be added if API is enabled
        # OPENEMR_SETTING_rest_fhir_api will be added if API is enabled
        # OpenEMR Patient Portal Configuration (conditionally set by deploy script)  
        # OPENEMR_SETTING_portal_onsite_two_address will be added if portal is enabled
        # OPENEMR_SETTING_portal_onsite_two_enable will be added if portal is enabled
        # OPENEMR_SETTING_ccda_alt_service_enable will be added if portal is enabled
        # OPENEMR_SETTING_rest_portal_api will be added if portal is enabled
        resources:
          requests:
            cpu: 250m
            memory: 512Mi
          limits:
            cpu: 1000m
            memory: 1Gi
        startupProbe:
          httpGet:
            path: /interface/login/login.php
            port: 80
            scheme: HTTP
          initialDelaySeconds: 60
          periodSeconds: 30
          timeoutSeconds: 10
          failureThreshold: 25
        readinessProbe:
          httpGet:
            path: /interface/login/login.php
            port: 80
            scheme: HTTP
          initialDelaySeconds: 240
          periodSeconds: 30
          timeoutSeconds: 10
          failureThreshold: 3
        livenessProbe:
          httpGet:
            path: /interface/login/login.php
            port: 80
            scheme: HTTP
          initialDelaySeconds: 300
          periodSeconds: 60
          timeoutSeconds: 10
          failureThreshold: 5
        volumeMounts:
        - name: openemr-sites
          mountPath: /var/www/localhost/htdocs/openemr/sites
        - name: openemr-ssl
          mountPath: /etc/ssl
        - name: openemr-letsencrypt
          mountPath: /etc/letsencrypt
      volumes:
      - name: db-credentials
        secret:
          secretName: openemr-db-credentials
      - name: redis-credentials
        secret:
          secretName: openemr-redis-credentials
      - name: openemr-sites
        persistentVolumeClaim:
          claimName: openemr-sites-pvc
      - name: openemr-ssl
        persistentVolumeClaim:
          claimName: openemr-ssl-pvc
      - name: openemr-letsencrypt
        persistentVolumeClaim:
          claimName: openemr-letsencrypt-pvc
      # EKS Auto Mode handles node selection, scheduling, and optimal placement automatically
      # Add tolerations for EKS Auto Mode nodes
      tolerations:
      - key: "CriticalAddonsOnly"
        operator: "Exists"
        effect: "NoSchedule"
      - key: "eks.amazonaws.com/compute-type"
        operator: "Equal"
        value: "auto-mode"
        effect: "NoSchedule"
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: openemr-sa
  namespace: openemr
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::${AWS_ACCOUNT_ID}:role/openemr-service-account-role
automountServiceAccountToken: true
EOF
    
    echo -e "${GREEN}✅ deployment.yaml restored to default state${NC}"
}

# Function to restore service.yaml to default state
restore_service_yaml() {
    echo -e "${YELLOW}Restoring service.yaml to default state...${NC}"
    
    # Try to restore from git first
    cd "$PROJECT_ROOT"
    if git checkout HEAD -- k8s/service.yaml 2>/dev/null; then
        echo -e "${GREEN}✅ service.yaml restored from git${NC}"
        return
    fi
    
    # Fallback: create from template
    cat > "$PROJECT_ROOT/k8s/service.yaml" << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: openemr-service
  namespace: openemr
  labels:
    app: openemr
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
    service.beta.kubernetes.io/aws-load-balancer-backend-protocol: "${BACKEND_PROTOCOL}"
    service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
    service.beta.kubernetes.io/aws-load-balancer-access-log-enabled: "true"
    service.beta.kubernetes.io/aws-load-balancer-access-log-s3-bucket-name: "${S3_BUCKET_NAME}"
    service.beta.kubernetes.io/aws-load-balancer-access-log-s3-bucket-prefix: "nlb-access-logs"
    # SSL annotations (conditionally enabled by deploy script)
    #    service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "443"
    #    service.beta.kubernetes.io/aws-load-balancer-ssl-cert: "${SSL_CERT_ARN}"
    #    service.beta.kubernetes.io/aws-load-balancer-ssl-negotiation-policy: "ELBSecurityPolicy-TLS-1-2-2017-01"
spec:
  type: LoadBalancer
  ports:
  - name: https
    port: 443
    targetPort: 443
    protocol: TCP
  selector:
    app: openemr
EOF
    
    echo -e "${GREEN}✅ service.yaml restored to default state${NC}"
}

# Function to restore other YAML files to default state
restore_other_yaml_files() {
    echo -e "${YELLOW}Restoring other YAML files to default state...${NC}"
    
    cd "$PROJECT_ROOT"
    
    # List of files to restore from git
    local files_to_restore=(
        "k8s/hpa.yaml"
        "k8s/storage.yaml" 
        "k8s/ingress.yaml"
        "k8s/logging.yaml"
        "k8s/configmap.yaml"
    )
    
    for file in "${files_to_restore[@]}"; do
        if [ -f "$file" ]; then
            if git checkout HEAD -- "$file" 2>/dev/null; then
                echo -e "${GREEN}✅ $(basename "$file") restored from git${NC}"
            else
                echo -e "${YELLOW}⚠️  Could not restore $(basename "$file") from git${NC}"
            fi
        fi
    done
}

# Function to clean up backup files
cleanup_backup_files() {
    echo -e "${YELLOW}Cleaning up .bak files...${NC}"
    
    find "$PROJECT_ROOT/k8s" -name "*.bak" -delete 2>/dev/null || true
    find "$PROJECT_ROOT/terraform" -name "*.bak" -delete 2>/dev/null || true
    
    echo -e "${GREEN}✅ Backup files cleaned up${NC}"
}

# Function to clean up generated files
cleanup_generated_files() {
    echo -e "${YELLOW}Cleaning up generated files...${NC}"
    
    # Remove credentials files (various patterns)
    rm -f "$PROJECT_ROOT/k8s/openemr-credentials.txt"
    rm -f "$PROJECT_ROOT/k8s/openemr-credentials-"*.txt
    
    # Remove log files
    rm -f "$PROJECT_ROOT/terraform/openemr-all-logs.txt"
    
    # Remove any temporary files
    find "$PROJECT_ROOT/k8s" -name "*.tmp" -delete 2>/dev/null || true
    find "$PROJECT_ROOT/terraform" -name "*.tmp" -delete 2>/dev/null || true
    
    echo -e "${GREEN}✅ Generated files cleaned up${NC}"
}

# Main restoration function
restore_defaults() {
    echo -e "${BLUE}🔄 OpenEMR Deployment Files Default State Restoration${NC}"
    echo -e "${BLUE}====================================================${NC}"
    echo ""
    
    restore_deployment_yaml
    restore_service_yaml
    restore_other_yaml_files
    cleanup_backup_files
    cleanup_generated_files
    
    echo ""
    echo -e "${GREEN}🎉 All deployment files restored to default state!${NC}"
    echo ""
    echo -e "${BLUE}📋 What was restored:${NC}"
    echo -e "${BLUE}• deployment.yaml - Reset to template with placeholders${NC}"
    echo -e "${BLUE}• service.yaml - Reset to template with placeholders${NC}"
    echo -e "${BLUE}• Other YAML files - Reset placeholders${NC}"
    echo -e "${BLUE}• Removed all .bak files${NC}"
    echo -e "${BLUE}• Removed generated credentials files${NC}"
    echo ""
    echo -e "${BLUE}📋 Files preserved:${NC}"
    echo -e "${BLUE}• terraform.tfvars (your configuration)${NC}"
    echo -e "${BLUE}• All infrastructure state${NC}"
    echo -e "${BLUE}• All documentation and scripts${NC}"
    echo ""
    echo -e "${BLUE}💡 Next steps:${NC}"
    echo -e "${BLUE}• Files are now ready for clean git tracking${NC}"
    echo -e "${BLUE}• Run './deploy.sh' to deploy with current configuration${NC}"
    echo -e "${BLUE}• Commit changes to git for clean version control${NC}"
}

# Parse command line arguments
FORCE=false
BACKUP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --force)
            FORCE=true
            shift
            ;;
        --backup)
            BACKUP=true
            shift
            ;;
        --help)
            show_help
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo -e "${YELLOW}Use --help for usage information${NC}"
            exit 1
            ;;
    esac
done

# Confirmation prompt unless --force is used
if [ "$FORCE" = false ]; then
    echo -e "${RED}⚠️  DEVELOPER WARNING:${NC}"
    echo -e "${RED}This will restore all deployment files to their git HEAD state.${NC}"
    echo -e "${RED}Any structural changes you've made to YAML files will be LOST.${NC}"
    echo ""
    echo -e "${YELLOW}This script will:${NC}"
    echo -e "${YELLOW}• Restore deployment files to their default template state${NC}"
    echo -e "${YELLOW}• Remove generated files and .bak files${NC}"
    echo -e "${YELLOW}• Preserve your terraform.tfvars and infrastructure${NC}"
    echo ""
    echo -e "${BLUE}Safe to use when:${NC}"
    echo -e "${BLUE}• Cleaning up after deployments${NC}"
    echo -e "${BLUE}• Preparing for git commits${NC}"
    echo -e "${BLUE}• You only changed configuration values${NC}"
    echo ""
    echo -e "${RED}DO NOT use when:${NC}"
    echo -e "${RED}• You're actively developing/modifying YAML file structure${NC}"
    echo -e "${RED}• You've made custom changes to deployment templates${NC}"
    echo -e "${RED}• You're working on new features in the YAML files${NC}"
    echo ""
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Operation cancelled.${NC}"
        exit 0
    fi
fi

# Create backup if requested
if [ "$BACKUP" = true ]; then
    create_backup
fi

# Run the restoration
restore_defaults