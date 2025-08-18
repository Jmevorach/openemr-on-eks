#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

CLUSTER_NAME=${CLUSTER_NAME:-"openemr-eks"}
AWS_REGION=${AWS_REGION:-"us-west-2"}
NAMESPACE=${NAMESPACE:-"openemr"}

# Get the script's directory and project root for path-independent operation
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "${GREEN}🧹 OpenEMR Clean Deployment Script${NC}"
echo -e "${GREEN}===================================${NC}"
echo ""
echo -e "${YELLOW}This script will clean up the current OpenEMR deployment${NC}"
echo -e "${YELLOW}Infrastructure (EKS, RDS, etc.) will remain intact${NC}"
echo -e "${RED}⚠️  DATABASE WARNING: This will DELETE ALL OpenEMR data from the database!${NC}"
echo -e "${RED}⚠️  This action cannot be undone!${NC}"
echo ""

# Confirm with user
read -p "Are you sure you want to clean the current deployment? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Cleanup cancelled${NC}"
    exit 0
fi

echo -e "${YELLOW}Starting cleanup...${NC}"
echo ""

# Delete OpenEMR namespace (this removes all resources in the namespace)
echo -e "${YELLOW}1. Removing OpenEMR namespace and all resources...${NC}"
if kubectl get namespace $NAMESPACE > /dev/null 2>&1; then
    kubectl delete namespace $NAMESPACE --timeout=300s
    echo -e "${GREEN}✅ OpenEMR namespace deleted${NC}"
else
    echo -e "${BLUE}ℹ️  OpenEMR namespace not found${NC}"
fi
echo ""

# Wait for namespace to be fully deleted
echo -e "${YELLOW}2. Waiting for namespace deletion to complete...${NC}"
while kubectl get namespace $NAMESPACE > /dev/null 2>&1; do
    echo -e "${BLUE}   Waiting for namespace deletion...${NC}"
    sleep 5
done
echo -e "${GREEN}✅ Namespace fully deleted${NC}"
echo ""

# Clean up OpenEMR database to prevent reconfiguration conflicts
echo -e "${YELLOW}3. Cleaning up OpenEMR database...${NC}"
echo -e "${RED}⚠️  WARNING: This will DELETE ALL OpenEMR data from the database!${NC}"
echo -e "${RED}⚠️  This action cannot be undone!${NC}"
echo ""

# Confirm database cleanup
read -p "Are you sure you want to DELETE ALL OpenEMR data from the database? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Database cleanup skipped - deployment may fail due to existing data${NC}"
    echo -e "${BLUE}   You can manually clean the database later if needed${NC}"
    echo ""
else
    echo -e "${YELLOW}Proceeding with database cleanup...${NC}"
    echo ""

    # Get database details from Terraform
    cd "$PROJECT_ROOT/terraform"
    if [ -f "terraform.tfstate" ]; then
        echo -e "${BLUE}   Getting database details from Terraform...${NC}"
        AURORA_ENDPOINT=$(terraform output -raw aurora_endpoint 2>/dev/null || echo "")
        AURORA_PASSWORD=$(terraform output -raw aurora_password 2>/dev/null || echo "")
        
        if [ -n "$AURORA_ENDPOINT" ] && [ -n "$AURORA_PASSWORD" ]; then
            echo -e "${BLUE}   Database endpoint: $AURORA_ENDPOINT${NC}"
            
            # Use a temporary MySQL pod to clean the database
            echo -e "${YELLOW}   Launching temporary MySQL pod to clean database...${NC}"
            
            # Create a temporary namespace for the cleanup pod
            TEMP_NAMESPACE="db-cleanup-temp"
            kubectl create namespace $TEMP_NAMESPACE --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true
            
            # Create a temporary secret with database credentials
            kubectl create secret generic temp-db-credentials \
                --namespace=$TEMP_NAMESPACE \
                --from-literal=mysql-host="$AURORA_ENDPOINT" \
                --from-literal=mysql-user="openemr" \
                --from-literal=mysql-password="$AURORA_PASSWORD" \
                --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true
            
            # Create a temporary MySQL pod for database cleanup
            cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: db-cleanup-pod
  namespace: $TEMP_NAMESPACE
spec:
  containers:
  - name: mysql-client
    image: mysql:8.0
    command: ['sh', '-c']
    args:
    - |
      echo "Waiting for MySQL connection..."
      until mysql -h \${MYSQL_HOST} -u \${MYSQL_USER} -p\${MYSQL_PASSWORD} -e "SELECT 1;" >/dev/null 2>&1; do
        sleep 2
      done
      echo "Connected to MySQL, cleaning database..."
      mysql -h \${MYSQL_HOST} -u \${MYSQL_USER} -p\${MYSQL_PASSWORD} -e "DROP DATABASE IF EXISTS openemr; CREATE DATABASE openemr CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
      echo "Database cleanup completed"
    env:
    - name: MYSQL_HOST
      valueFrom:
        secretKeyRef:
          name: temp-db-credentials
          key: mysql-host
    - name: MYSQL_USER
      valueFrom:
        secretKeyRef:
          name: temp-db-credentials
          key: mysql-user
    - name: MYSQL_PASSWORD
      valueFrom:
        secretKeyRef:
          name: temp-db-credentials
          key: mysql-password
  restartPolicy: Never
EOF

            # Wait for the pod to complete
            echo -e "${BLUE}   Waiting for database cleanup to complete...${NC}"
            kubectl wait --for=condition=Ready pod/db-cleanup-pod -n $TEMP_NAMESPACE --timeout=60s 2>/dev/null || true
            
            # Check the pod logs and status
            # Wait a bit more for the pod to complete its execution
            sleep 5
            
            # Check if the pod completed successfully by looking at the logs
            if kubectl logs db-cleanup-pod -n $TEMP_NAMESPACE 2>/dev/null | grep -q "Database cleanup completed"; then
                echo -e "${GREEN}✅ OpenEMR database cleaned successfully via temporary MySQL pod${NC}"
                # Show the logs
                echo -e "${BLUE}   Cleanup logs:${NC}"
                kubectl logs db-cleanup-pod -n $TEMP_NAMESPACE
            else
                echo -e "${YELLOW}⚠️  Database cleanup pod may not have completed successfully${NC}"
                echo -e "${BLUE}   Pod status:${NC}"
                kubectl get pod db-cleanup-pod -n $TEMP_NAMESPACE
                echo -e "${BLUE}   Pod logs:${NC}"
                kubectl logs db-cleanup-pod -n $TEMP_NAMESPACE || echo "No logs available"
                echo -e "${BLUE}   Database cleanup will be handled during deployment${NC}"
            fi
            
            # Clean up temporary resources
            echo -e "${BLUE}   Cleaning up temporary resources...${NC}"
            kubectl delete namespace $TEMP_NAMESPACE --timeout=30s 2>/dev/null || true
        else
            echo -e "${YELLOW}⚠️  Could not get database details from Terraform${NC}"
            echo -e "${BLUE}   Database cleanup will be handled during deployment${NC}"
        fi
    else
        echo -e "${BLUE}ℹ️  Terraform state not found - skipping database cleanup${NC}"
    fi
    
    cd "$SCRIPT_DIR"
fi

# Clean up any orphaned PVCs (in case they weren't deleted with namespace)
echo -e "${YELLOW}4. Checking for orphaned PVCs...${NC}"
ORPHANED_PVCS=$(kubectl get pvc --all-namespaces | grep openemr || echo "")
if [ -n "$ORPHANED_PVCS" ]; then
    echo -e "${YELLOW}Found orphaned PVCs, cleaning up...${NC}"
    kubectl get pvc --all-namespaces | grep openemr | awk '{print $1 " " $2}' | while read namespace pvc; do
        kubectl delete pvc $pvc -n $namespace --timeout=60s || echo "Failed to delete $pvc"
    done
else
    echo -e "${GREEN}✅ No orphaned PVCs found${NC}"
fi
echo ""

# Clean up any orphaned PVs
echo -e "${YELLOW}5. Checking for orphaned PVs...${NC}"
ORPHANED_PVS=$(kubectl get pv | grep openemr || echo "")
if [ -n "$ORPHANED_PVS" ]; then
    echo -e "${YELLOW}Found orphaned PVs, cleaning up...${NC}"
    kubectl get pv | grep openemr | awk '{print $1}' | while read pv; do
        kubectl delete pv $pv --timeout=60s || echo "Failed to delete $pv"
    done
else
    echo -e "${GREEN}✅ No orphaned PVs found${NC}"
fi
echo ""

# Restart EFS CSI controller to clear any cached state
echo -e "${YELLOW}6. Restarting EFS CSI controller to clear cached state...${NC}"
kubectl rollout restart deployment efs-csi-controller -n kube-system
kubectl rollout status deployment efs-csi-controller -n kube-system --timeout=120s
echo -e "${GREEN}✅ EFS CSI controller restarted${NC}"
echo ""

# Clean up any backup files from previous deployments
echo -e "${YELLOW}7. Cleaning up backup files...${NC}"
cd ../k8s
rm -f *.yaml.bak
rm -f openemr-credentials*.txt
echo -e "${GREEN}✅ Backup files cleaned${NC}"
echo ""

echo -e "${GREEN}🎉 Cleanup completed successfully!${NC}"
echo ""
echo -e "${BLUE}📋 Next Steps:${NC}"
echo -e "${BLUE}1. Run a fresh deployment:${NC}"
echo -e "${BLUE}   cd ../k8s && ./deploy.sh${NC}"
echo -e "${BLUE}2. Monitor the deployment:${NC}"
echo -e "${BLUE}   kubectl get pods -n openemr -w${NC}"
echo -e "${BLUE}3. Validate EFS CSI if needed:${NC}"
echo -e "${BLUE}   cd ../scripts && ./validate-efs-csi.sh${NC}"
echo ""
echo -e "${GREEN}Infrastructure (EKS cluster, RDS, etc.) remains intact${NC}"