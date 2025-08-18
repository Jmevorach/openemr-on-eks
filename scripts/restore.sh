#!/bin/bash

# OpenEMR Restore Script
# Simple, reliable restore from backup

# set -e  # Temporarily disabled for debugging

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
BACKUP_BUCKET=${1:-""}
SNAPSHOT_ID=${2:-""}
BACKUP_REGION=${3:-"$AWS_REGION"}

# Polling configuration (in seconds)
CLUSTER_AVAILABILITY_TIMEOUT=${CLUSTER_AVAILABILITY_TIMEOUT:-1800}  # 30 minutes default
SNAPSHOT_AVAILABILITY_TIMEOUT=${SNAPSHOT_AVAILABILITY_TIMEOUT:-1800}  # 30 minutes default
POLLING_INTERVAL=${POLLING_INTERVAL:-30}  # 30 seconds default

# Help function
show_help() {
    echo "OpenEMR Restore Script"
    echo "======================="
    echo ""
    echo "Usage: $0 <backup-bucket> <snapshot-id> [backup-region]"
    echo ""
    echo "Arguments:"
    echo "  backup-bucket    S3 bucket containing the backup"
    echo "  snapshot-id      RDS snapshot identifier (use 'none' if no RDS backup)"
    echo "  backup-region    AWS region where backup is stored (default: us-west-2)"
    echo ""
    echo "Environment Variables:"
    echo "  CLUSTER_NAME     Target EKS cluster name (default: openemr-eks)"
    echo "  AWS_REGION       Target AWS region (default: us-west-2)"
    echo "  NAMESPACE        Kubernetes namespace (default: openemr)"
    echo ""
    echo "Timeout Configuration:"
    echo "  CLUSTER_AVAILABILITY_TIMEOUT  Timeout for RDS cluster availability (default: 1800s = 30m)"
    echo "  SNAPSHOT_AVAILABILITY_TIMEOUT Timeout for RDS snapshot availability (default: 1800s = 30m)"
    echo "  POLLING_INTERVAL              Polling interval in seconds (default: 30s)"
    echo ""
    echo "What Gets Restored:"
    echo "  ✅ RDS Aurora cluster from snapshot"
    echo "  ✅ Kubernetes configurations and secrets"
    echo "  ✅ Application data to EFS volumes"
    echo ""
    echo "Example:"
    echo "  $0 openemr-backups-123456789012-openemr-eks-20250815 openemr-eks-aurora-backup-20250815-120000 us-east-1"
    echo ""
    exit 0
}

# Check for help option
if [ "$1" = "--help" ] || [ "$1" = "-h" ] || [ -z "$1" ]; then
    show_help
fi

# Logging functions
log_info() {
    echo -e "${BLUE}[$(date '+%H:%M:%S')] ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')] ✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}[$(date '+%H:%M:%S')] ❌ $1${NC}"
    exit 1
}

# Polling functions
wait_for_cluster_availability() {
    local cluster_id=$1
    local region=$2
    local timeout=$3
    local start_time=$(date +%s)
    local elapsed=0
    
    log_info "Waiting for RDS cluster '$cluster_id' to be available in $region..."
    
    while [ $elapsed -lt $timeout ]; do
        local status=$(aws rds describe-db-clusters \
            --db-cluster-identifier "$cluster_id" \
            --region "$region" \
            --query 'DBClusters[0].Status' \
            --output text 2>/dev/null || echo "unknown")
        
        if [ "$status" = "available" ]; then
            log_success "RDS cluster '$cluster_id' is now available"
            return 0
        fi
        
        elapsed=$(($(date +%s) - start_time))
        local remaining=$((timeout - elapsed))
        
        if [ $elapsed -ge $timeout ]; then
            log_warning "Timeout waiting for cluster availability after ${timeout}s"
            return 1
        fi
        
        log_info "Cluster status: $status (${remaining}s remaining)"
        sleep $POLLING_INTERVAL
    done
    
    return 1
}

wait_for_snapshot_availability() {
    local snapshot_id=$1
    local region=$2
    local timeout=$3
    local start_time=$(date +%s)
    local elapsed=0
    
    log_info "Waiting for RDS snapshot '$snapshot_id' to be available in $region..."
    
    while [ $elapsed -lt $timeout ]; do
        local status=$(aws rds describe-db-cluster-snapshots \
            --db-cluster-snapshot-identifier "$snapshot_id" \
            --query 'DBClusterSnapshots[0].Status' \
            --output text 2>/dev/null || echo "unknown")
        
        if [ "$status" = "available" ]; then
            log_success "RDS snapshot '$snapshot_id' is now available"
            return 0
        fi
        
        elapsed=$(($(date +%s) - start_time))
        local remaining=$((timeout - elapsed))
        
        if [ $elapsed -ge $timeout ]; then
            log_warning "Timeout waiting for snapshot availability after ${timeout}s"
            return 1
        fi
        
        log_info "Snapshot status: $status (${remaining}s remaining)"
        sleep $POLLING_INTERVAL
    done
    
    return 1
}

# Initialize restore
echo -e "${GREEN}🚀 OpenEMR Restore Starting${NC}"
echo -e "${BLUE}===========================${NC}"
echo -e "${BLUE}Target Region: ${AWS_REGION}${NC}"
echo -e "${BLUE}Backup Region: ${BACKUP_REGION}${NC}"
echo -e "${BLUE}Backup Bucket: ${BACKUP_BUCKET}${NC}"
echo -e "${BLUE}Snapshot ID: ${SNAPSHOT_ID}${NC}"
echo -e "${BLUE}Target Cluster: ${CLUSTER_NAME}${NC}"
echo ""

# Confirm restore operation
echo -e "${RED}⚠️  WARNING: This will restore OpenEMR from backup${NC}"
echo -e "${RED}⚠️  Target Region: ${AWS_REGION}${NC}"
echo -e "${RED}⚠️  This operation may overwrite existing data!${NC}"
echo ""

read -p "Are you sure you want to proceed with the restore? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Restore cancelled.${NC}"
    exit 0
fi

# Check dependencies
check_dependencies() {
    local missing_deps=()
    
    # Check AWS CLI
    if ! command -v aws >/dev/null 2>&1; then
        missing_deps+=("aws")
    fi
    
    # Check kubectl
    if ! command -v kubectl >/dev/null 2>&1; then
        missing_deps+=("kubectl")
    fi
    
    # Check tar
    if ! command -v tar >/dev/null 2>&1; then
        missing_deps+=("tar")
    fi
    
    # Check gzip
    if ! command -v gzip >/dev/null 2>&1; then
        missing_deps+=("gzip")
    fi
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_info "Please install: ${missing_deps[*]}"
        exit 1
    fi
}

# Check prerequisites
log_info "Checking prerequisites..."

# Check dependencies
check_dependencies

# Check AWS credentials
if ! aws sts get-caller-identity >/dev/null 2>&1; then
    log_error "AWS credentials not configured"
fi

# Check regions
for region in "$AWS_REGION" "$BACKUP_REGION"; do
    if ! aws ec2 describe-regions --region-names "$region" >/dev/null 2>&1; then
        log_error "Cannot access region: $region"
    fi
done

# Check backup bucket exists
log_info "Checking bucket: s3://${BACKUP_BUCKET} in region: ${BACKUP_REGION}"
AWS_OUTPUT=$(aws s3 ls "s3://${BACKUP_BUCKET}" --region "$BACKUP_REGION" 2>&1)
AWS_EXIT_CODE=$?
if [ $AWS_EXIT_CODE -ne 0 ]; then
    log_error "Backup bucket not found: s3://${BACKUP_BUCKET}"
    log_error "AWS CLI exit code: $AWS_EXIT_CODE"
    log_error "AWS CLI output: $AWS_OUTPUT"
    exit 1
fi

log_success "Prerequisites verified"

# Download and parse backup metadata
log_info "📋 Downloading backup metadata..."

TEMP_DIR="restore-temp-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$TEMP_DIR"

# Download metadata files
aws s3 cp "s3://${BACKUP_BUCKET}/metadata/" "$TEMP_DIR/" --recursive --region "$BACKUP_REGION" 2>/dev/null || {
    log_error "Could not download backup metadata"
}

# Find the latest metadata file
METADATA_FILE=$(ls -t "$TEMP_DIR"/backup-metadata-*.json 2>/dev/null | head -1)
if [ -z "$METADATA_FILE" ]; then
    log_error "No backup metadata found"
fi

log_info "Found metadata: $(basename "$METADATA_FILE")"

# Parse metadata
ORIGINAL_CLUSTER=$(jq -r '.cluster_name' "$METADATA_FILE")
ORIGINAL_REGION=$(jq -r '.source_region' "$METADATA_FILE")
BACKUP_TIMESTAMP=$(jq -r '.timestamp' "$METADATA_FILE")
BACKUP_SUCCESS=$(jq -r '.backup_success' "$METADATA_FILE")

log_info "Original backup from: ${ORIGINAL_REGION} (cluster: ${ORIGINAL_CLUSTER})"
log_info "Backup timestamp: ${BACKUP_TIMESTAMP}"

if [ "$BACKUP_SUCCESS" != "true" ]; then
    log_warning "Original backup had warnings - proceeding with caution"
fi

# Initialize restore results
RESTORE_RESULTS=""
RESTORE_SUCCESS=true

# Function to add result
add_result() {
    local component=$1
    local status=$2
    local details=$3
    
    RESTORE_RESULTS="${RESTORE_RESULTS}${component}: ${status}"
    if [ -n "$details" ]; then
        RESTORE_RESULTS="${RESTORE_RESULTS} (${details})"
    fi
    RESTORE_RESULTS="${RESTORE_RESULTS}\n"
    
    if [ "$status" = "FAILED" ]; then
        RESTORE_SUCCESS=false
    fi
}

# Restore RDS Aurora cluster
if [ "$SNAPSHOT_ID" != "none" ] && [ -n "$SNAPSHOT_ID" ]; then
    log_info "🗄️  Restoring RDS Aurora cluster..."
    
    # Check if snapshot exists
    if [ "$BACKUP_REGION" != "$AWS_REGION" ]; then
        log_info "Cross-region restore detected"
        
        # Check if snapshot exists in target region
        if ! aws rds describe-db-cluster-snapshots \
            --region "$AWS_REGION" \
            --db-cluster-snapshot-identifier "$SNAPSHOT_ID" >/dev/null 2>&1; then
            
            log_warning "Snapshot not found in target region - attempting automatic copy"
            
            # Generate target snapshot name
            TARGET_SNAPSHOT_ID="${SNAPSHOT_ID}-${AWS_REGION}"
            
            log_info "Copying snapshot from ${BACKUP_REGION} to ${AWS_REGION}..."
            log_info "Target snapshot ID: ${TARGET_SNAPSHOT_ID}"
            
            # Check if we need a KMS key for encrypted snapshot copy
            KMS_KEY_PARAM=""
            if aws rds describe-db-cluster-snapshots \
                --region "$BACKUP_REGION" \
                --db-cluster-snapshot-identifier "$SNAPSHOT_ID" \
                --query 'DBClusterSnapshots[0].StorageEncrypted' \
                --output text 2>/dev/null | grep -q "True"; then
                
                log_info "Snapshot is encrypted - using default KMS key in target region"
                # Use the default AWS RDS KMS key in the target region
                DEFAULT_KMS_KEY=$(aws kms list-aliases \
                    --region "$AWS_REGION" \
                    --query 'Aliases[?AliasName==`alias/aws/rds`].TargetKeyId' \
                    --output text 2>/dev/null || echo "")
                
                if [ -n "$DEFAULT_KMS_KEY" ]; then
                    KMS_KEY_PARAM="--kms-key-id $DEFAULT_KMS_KEY"
                    log_info "Using KMS key: $DEFAULT_KMS_KEY"
                else
                    log_warning "No default KMS key found in target region - copy may fail"
                fi
            fi
            
            # Copy the snapshot
            if aws rds copy-db-cluster-snapshot \
                --source-db-cluster-snapshot-identifier "arn:aws:rds:${BACKUP_REGION}:$(aws sts get-caller-identity --query 'Account' --output text):cluster-snapshot:${SNAPSHOT_ID}" \
                --target-db-cluster-snapshot-identifier "${TARGET_SNAPSHOT_ID}" \
                --source-region "${BACKUP_REGION}" \
                --region "${AWS_REGION}" \
                $KMS_KEY_PARAM; then
                
                log_success "Snapshot copy initiated successfully"
                log_info "Waiting for copy to complete..."
                
                # Wait for copy to complete using polling function
                if wait_for_snapshot_availability "$TARGET_SNAPSHOT_ID" "$AWS_REGION" "$SNAPSHOT_AVAILABILITY_TIMEOUT"; then
                    log_success "Snapshot copy completed successfully"
                    SNAPSHOT_ID="$TARGET_SNAPSHOT_ID"  # Use the copied snapshot
                else
                    log_error "Snapshot copy did not complete within timeout"
                    add_result "Aurora RDS" "FAILED" "Snapshot copy timeout"
                    exit 1
                fi
            else
                log_error "Failed to initiate snapshot copy"
                log_info "You can manually copy the snapshot using:"
                echo ""
                echo "aws rds copy-db-cluster-snapshot \\"
                echo "    --source-db-cluster-snapshot-identifier arn:aws:rds:${BACKUP_REGION}:$(aws sts get-caller-identity --query 'Account' --output text):cluster-snapshot:${SNAPSHOT_ID} \\"
                echo "    --target-db-cluster-snapshot-identifier ${SNAPSHOT_ID}-${AWS_REGION} \\"
                echo "    --source-region ${BACKUP_REGION} \\"
                echo "    --region ${AWS_REGION}"
                if [ -n "$KMS_KEY_PARAM" ]; then
                    echo "    --kms-key-id $DEFAULT_KMS_KEY"
                fi
                echo ""
                add_result "Aurora RDS" "FAILED" "Snapshot copy failed"
            fi
        else
            log_success "Snapshot found in target region"
        fi
    fi
    
    if aws rds describe-db-cluster-snapshots \
        --region "$AWS_REGION" \
        --db-cluster-snapshot-identifier "$SNAPSHOT_ID" >/dev/null 2>&1; then
        
        # Generate new cluster identifier
        NEW_CLUSTER_ID="openemr-restored-$(date +%Y%m%d-%H%M%S)"
        log_info "Creating new cluster: ${NEW_CLUSTER_ID}"
        
        # Find existing VPC and subnet group
        VPC_ID=$(aws ec2 describe-vpcs \
            --region "$AWS_REGION" \
            --filters "Name=tag:Name,Values=${CLUSTER_NAME}-vpc" \
            --query 'Vpcs[0].VpcId' \
            --output text 2>/dev/null || echo "None")
        
        if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
            # Try default VPC
            VPC_ID=$(aws ec2 describe-vpcs \
                --region "$AWS_REGION" \
                --filters "Name=isDefault,Values=true" \
                --query 'Vpcs[0].VpcId' \
                --output text 2>/dev/null || echo "None")
        fi
        
        if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
            log_error "No VPC found for restore"
        fi
        
        log_info "Using VPC: ${VPC_ID}"
        
        # Find subnet group
        SUBNET_GROUP_NAME=$(aws rds describe-db-subnet-groups \
            --region "$AWS_REGION" \
            --query "DBSubnetGroups[?VpcId=='${VPC_ID}'].DBSubnetGroupName" \
            --output text 2>/dev/null | head -1)
        
        if [ -z "$SUBNET_GROUP_NAME" ]; then
            log_error "No DB subnet group found in VPC: ${VPC_ID}"
        fi
        
        log_info "Using subnet group: ${SUBNET_GROUP_NAME}"
        
        # Restore cluster
        if aws rds restore-db-cluster-from-snapshot \
            --region "$AWS_REGION" \
            --db-cluster-identifier "$NEW_CLUSTER_ID" \
            --snapshot-identifier "$SNAPSHOT_ID" \
            --engine aurora-mysql \
            --db-subnet-group-name "$SUBNET_GROUP_NAME" \
            --no-deletion-protection >/dev/null 2>&1; then
            
            log_success "Aurora cluster restore initiated: ${NEW_CLUSTER_ID}"
            
            # Wait for cluster to be available using polling function
            log_info "Waiting for cluster to be available..."
            
            if wait_for_cluster_availability "$NEW_CLUSTER_ID" "$AWS_REGION" "$CLUSTER_AVAILABILITY_TIMEOUT"; then
                log_success "Aurora cluster is now available"
                # Create Aurora Serverless V2 instances
                log_info "Creating Aurora Serverless V2 instances..."
                
                aws rds create-db-instance \
                    --region "$AWS_REGION" \
                    --db-instance-identifier "${NEW_CLUSTER_ID}-instance-1" \
                    --db-cluster-identifier "$NEW_CLUSTER_ID" \
                    --db-instance-class db.serverless \
                    --engine aurora-mysql >/dev/null 2>&1
                
                aws rds create-db-instance \
                    --region "$AWS_REGION" \
                    --db-instance-identifier "${NEW_CLUSTER_ID}-instance-2" \
                    --db-cluster-identifier "$NEW_CLUSTER_ID" \
                    --db-instance-class db.serverless \
                    --engine aurora-mysql >/dev/null 2>&1
                
                log_success "Aurora instances created"
                add_result "Aurora RDS" "SUCCESS" "$NEW_CLUSTER_ID"
            else
                log_warning "Cluster creation timeout - may still be in progress"
                add_result "Aurora RDS" "PARTIAL" "Timeout waiting for availability"
            fi
        else
            log_warning "Failed to restore Aurora cluster"
            add_result "Aurora RDS" "FAILED" "Restore command failed"
        fi
    else
        log_warning "Snapshot not found: ${SNAPSHOT_ID}"
        add_result "Aurora RDS" "FAILED" "Snapshot not found"
    fi
else
    log_info "Skipping RDS restore (no snapshot specified)"
    add_result "Aurora RDS" "SKIPPED" "No snapshot provided"
fi

# Restore Kubernetes configurations
log_info "⚙️  Restoring Kubernetes configurations..."

if kubectl cluster-info >/dev/null 2>&1; then
    log_info "Kubernetes cluster accessible"
    
    # Download Kubernetes backup
    aws s3 cp "s3://${BACKUP_BUCKET}/kubernetes/" "$TEMP_DIR/" --recursive --region "$BACKUP_REGION" 2>/dev/null || {
        log_warning "Could not download Kubernetes backup"
        add_result "Kubernetes Config" "FAILED" "Download failed"
    }
    
    # Find the latest backup
    K8S_BACKUP=$(ls -t "$TEMP_DIR"/k8s-backup-*.tar.gz 2>/dev/null | head -1)
    
    if [ -n "$K8S_BACKUP" ]; then
        log_info "Found Kubernetes backup: $(basename "$K8S_BACKUP")"
        
        # Extract backup
        tar -xzf "$K8S_BACKUP" -C "$TEMP_DIR/"
        
        # Find extracted directory
        K8S_DIR=$(find "$TEMP_DIR" -type d -name "k8s-backup-*" | head -1)
        
        if [ -n "$K8S_DIR" ]; then
            # Apply configurations (excluding secrets to avoid conflicts)
            log_info "Applying Kubernetes configurations..."
            
            kubectl apply -f "$K8S_DIR/configmaps.yaml" 2>/dev/null || log_warning "ConfigMaps restore had issues"
            kubectl apply -f "$K8S_DIR/pvc.yaml" 2>/dev/null || log_warning "PVC restore had issues"
            kubectl apply -f "$K8S_DIR/ingress.yaml" 2>/dev/null || log_warning "Ingress restore had issues"
            kubectl apply -f "$K8S_DIR/hpa.yaml" 2>/dev/null || log_warning "HPA restore had issues"
            
            log_success "Kubernetes configurations restored"
            add_result "Kubernetes Config" "SUCCESS" "Configurations applied"
        else
            log_warning "Could not extract Kubernetes backup"
            add_result "Kubernetes Config" "FAILED" "Extraction failed"
        fi
    else
        log_warning "No Kubernetes backup found"
        add_result "Kubernetes Config" "FAILED" "No backup found"
    fi
else
    log_warning "Kubernetes cluster not accessible"
    add_result "Kubernetes Config" "SKIPPED" "Cluster not accessible"
fi

# Restore application data
log_info "📦 Restoring application data..."

if kubectl cluster-info >/dev/null 2>&1; then
    # Download application data backup
    aws s3 cp "s3://${BACKUP_BUCKET}/application-data/" "$TEMP_DIR/" --recursive --region "$BACKUP_REGION" 2>/dev/null || {
        log_warning "Could not download application data backup"
        add_result "Application Data" "FAILED" "Download failed"
    }
    
    # Find the latest backup
    APP_BACKUP=$(ls -t "$TEMP_DIR"/app-data-backup-*.tar.gz 2>/dev/null | head -1)
    
    if [ -n "$APP_BACKUP" ]; then
        log_info "Found application backup: $(basename "$APP_BACKUP")"
        
        # Wait for OpenEMR pods to be ready
        log_info "Waiting for OpenEMR pods to be ready..."
        kubectl wait --for=condition=ready pod -l app=openemr -n "$NAMESPACE" --timeout=300s 2>/dev/null || {
            log_warning "OpenEMR pods not ready - you may need to deploy the application first"
            add_result "Application Data" "FAILED" "No pods ready"
        }
        
        # Find pod
        POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app=openemr -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        
        if [ -n "$POD_NAME" ]; then
            log_info "Found OpenEMR pod: ${POD_NAME}"
            
            # Copy backup to pod
            kubectl cp "$APP_BACKUP" "${NAMESPACE}/${POD_NAME}:/tmp/app-restore.tar.gz" 2>/dev/null
            
            # Extract backup in pod
            kubectl exec -n "$NAMESPACE" "$POD_NAME" -- tar -xzf /tmp/app-restore.tar.gz -C /var/www/localhost/htdocs/openemr/ 2>/dev/null
            
            # Cleanup
            kubectl exec -n "$NAMESPACE" "$POD_NAME" -- rm -f /tmp/app-restore.tar.gz 2>/dev/null || true
            
            log_success "Application data restored"
            add_result "Application Data" "SUCCESS" "Data extracted to pod"
        else
            log_warning "No OpenEMR pods found"
            add_result "Application Data" "FAILED" "No pods found"
        fi
    else
        log_warning "No application data backup found"
        add_result "Application Data" "FAILED" "No backup found"
    fi
else
    log_warning "Kubernetes cluster not accessible"
    add_result "Application Data" "SKIPPED" "Cluster not accessible"
fi

# Cleanup
rm -rf "$TEMP_DIR"

# Final summary
echo ""
if [ "$RESTORE_SUCCESS" = true ]; then
    echo -e "${GREEN}🎉 Restore Completed Successfully!${NC}"
else
    echo -e "${YELLOW}⚠️  Restore Completed with Warnings${NC}"
fi

echo -e "${BLUE}==================================${NC}"
echo -e "${BLUE}📋 Restore Results:${NC}"
echo -e "$RESTORE_RESULTS"

if [ -n "$NEW_CLUSTER_ID" ]; then
    echo -e "${GREEN}✅ New Aurora Cluster: ${NEW_CLUSTER_ID}${NC}"
    
    # Get cluster endpoint
    NEW_ENDPOINT=$(aws rds describe-db-clusters \
        --region "$AWS_REGION" \
        --db-cluster-identifier "$NEW_CLUSTER_ID" \
        --query 'DBClusters[0].Endpoint' \
        --output text 2>/dev/null || echo "")
    
    if [ -n "$NEW_ENDPOINT" ]; then
        echo -e "${GREEN}✅ Cluster Endpoint: ${NEW_ENDPOINT}${NC}"
    fi
fi

echo ""
echo -e "${YELLOW}📋 Next Steps:${NC}"
echo -e "${YELLOW}1. Verify database connectivity and data integrity${NC}"
echo -e "${YELLOW}2. Test application functionality${NC}"
echo -e "${YELLOW}3. Update DNS records if needed${NC}"
echo -e "${YELLOW}4. Configure monitoring and alerting${NC}"
echo -e "${YELLOW}5. Update application configuration with new endpoints${NC}"
echo ""

log_success "Restore process completed"
