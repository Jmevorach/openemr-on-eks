# OpenEMR EKS Auto Mode Troubleshooting Guide

This comprehensive guide helps diagnose and resolve issues with OpenEMR on EKS Auto Mode, with specific focus on healthcare compliance and Auto Mode-specific challenges.

## 📋 Table of Contents

### **🔧 Quick Diagnostics**
- [Essential Validation Scripts](#essential-validation-scripts)
- [Complete Scripts Reference for Troubleshooting](#complete-scripts-reference-for-troubleshooting)
- [Script-Based Troubleshooting Workflow](#script-based-troubleshooting-workflow)
- [Auto Mode Health Check](#auto-mode-health-check)

### **🚨 Common Issues and Solutions**
- [Monitoring Installation Warnings](#1-monitoring-installation-warnings)
- [Cannot Access Cluster](#2-cannot-access-cluster)
- [Terraform Deployment Failures](#3-terraform-deployment-failures)
- [Pods Not Starting](#4-pods-not-starting)
- [Database Connection Issues](#5-database-connection-issues)
- [EKS Auto Mode Specific Issues](#6-eks-auto-mode-specific-issues)
- [Common Error Messages Reference](#-common-error-messages-reference)


### **💰 Cost and Performance**
- [Unexpected High Costs](#unexpected-high-costs)
- [Performance Degradation](#performance-degradation)

### **🔍 Advanced Debugging**
- [Security Incident Response](#-security-incident-response)
- [Best Practices for Error Prevention](#-best-practices-for-error-prevention)

### **📞 Getting Help**
- [Getting Help](#-getting-help-1)

---

## Essential Validation Scripts

### Run These First

```bash
# 1. Comprehensive system validation
cd scripts
./validate-deployment.sh

# 2. Storage-specific validation (if pods are pending)
./validate-efs-csi.sh

# 3. Cluster access check
./cluster-security-manager.sh check-ip

# 4. Clean deployment if corrupted
# WARNING: ONLY USE IN DEVELOPMENT OR AFTER BACKING UP DATA! This will result in data loss.
./clean-deployment.sh
```

### Complete Scripts Reference for Troubleshooting

#### **Application Issues**
```bash
# Check OpenEMR version and available updates
./check-openemr-versions.sh --latest

# Verify feature configuration
./openemr-feature-manager.sh status all

# Enable/disable features for testing
./openemr-feature-manager.sh disable api    # Disable API if causing issues
./openemr-feature-manager.sh enable portal  # Enable portal for testing
```

#### **Infrastructure Issues**
```bash
# Comprehensive deployment validation
./validate-deployment.sh

# Storage system validation
./validate-efs-csi.sh

# Clean and reset deployment
# WARNING: ONLY USE IN DEVELOPMENT OR AFTER BACKING UP DATA! This will result in data loss.
./clean-deployment.sh
```

#### **Security and Access Issues**
```bash
# Check cluster access status
./cluster-security-manager.sh status

# Check if IP changed
./cluster-security-manager.sh check-ip

# Temporarily enable access (DEVELOPMENT ONLY)
./cluster-security-manager.sh enable

# Check SSL certificate status
./ssl-cert-manager.sh status

# Check self-signed certificate renewal
./ssl-renewal-manager.sh status
```

#### **Backup and Recovery Issues**

See comprehensive documentation on the backup and restore system [here](../docs/BACKUP_RESTORE_GUIDE.md).

```bash
# Create emergency backup
./backup.sh

# Restore from backup (disaster recovery)
./restore.sh <backup-bucket> <snapshot-id> <backup-region>
```

### Script-Based Troubleshooting Workflow

#### **Step 1: Initial Diagnosis**
```bash
cd scripts

# Run comprehensive validation
./validate-deployment.sh

# If validation fails, check specific areas:
# - AWS credentials
# - Cluster connectivity  
# - Infrastructure status
# - Application health
```

#### **Step 2: Specific Issue Diagnosis**
```bash
# For pod/storage issues:
./validate-efs-csi.sh

# For access issues:
./cluster-security-manager.sh check-ip
./cluster-security-manager.sh status

# For feature-related issues:
./openemr-feature-manager.sh status all

# For SSL/certificate issues:
./ssl-cert-manager.sh status
./ssl-renewal-manager.sh status
```

#### **Step 3: Resolution Actions**
```bash
# Clean deployment if corrupted:
# WARNING: ONLY USE IN DEVELOPMENT OR AFTER BACKING UP DATA! This will result in data loss.
./clean-deployment.sh

# DEVELOPMENT ONLY! In production this should never be enabled; use more secure management methods instead.
# Reset cluster access:
./cluster-security-manager.sh enable  # Then disable after work

# Update OpenEMR version:
./check-openemr-versions.sh --latest
# Update terraform.tfvars with new version
# Run terraform apply and k8s/deploy.sh

# Restore deployment files to clean state:
./restore-defaults.sh --backup

# Restore from backup if needed:
./restore.sh <backup-bucket> <snapshot-id> <backup-region>
```

### Auto Mode Health Check

```bash
#!/bin/bash
# Save as check-auto-mode.sh

echo "=== EKS Auto Mode Health Check ==="

# Check cluster compute configuration
echo "Checking Auto Mode status..."
aws eks describe-cluster --name openemr-eks \
  --query 'cluster.computeConfig' \
  --output json

# Check for nodeclaims
echo "Checking nodeclaims..."
kubectl get nodeclaim

# Check for node pools
echo "Checking node pools..."
kubectl get nodepool

# Check for pending pods that might need Auto Mode provisioning
echo "Checking for pending pods..."
kubectl get pods --all-namespaces --field-selector=status.phase=Pending
```

## 🚨 Common Issues and Solutions

### 1. Monitoring Installation Warnings

#### **Warning: "OpenEMR dashboard not configured"**
```
[WARN] ⚠️ OpenEMR dashboard not configured
```

**Explanation:** This is a non-critical warning indicating that a custom OpenEMR Grafana dashboard hasn't been created yet.

For more information search [install-monitoring.sh](../monitoring/install-monitoring.sh) for "OpenEMR dashboard not configured".

**Impact:** 
- ✅ All monitoring functionality works normally
- ✅ Prometheus collects OpenEMR metrics
- ✅ Grafana displays standard Kubernetes dashboards
- ⚠️ No OpenEMR-specific dashboard available

**Resolution:** 
- This warning can be safely ignored
- The monitoring stack is fully functional
- Custom OpenEMR dashboards can be added later if needed
- This warning will go away if you specify a specific "grafana-dashboard-openemr" configmap to make a custom dashboard for OpenEMR and it will be applied automatically as part of the install-monitoring.sh script.

### 2. Cannot Access Cluster

#### Symptoms
```
Unable to connect to the server: dial tcp: i/o timeout
error: You must be logged in to the server (Unauthorized)
The connection to the server was refused
```

#### Root Causes
- **IP address change**
- **Cluster endpoint disabled**
- **AWS credentials expired**
- **Network connectivity issues**

#### Solutions

**Quick Fix - Update IP Access:**
```bash
# Check your current IP vs allowed
cd scripts
./cluster-security-manager.sh check-ip

# If different, update access
./cluster-security-manager.sh enable

# Verify connection
kubectl get nodes
```

### 3. Terraform Deployment Failures

#### Issue: Auto Mode Not Available

**Error:**
```
Error: error creating EKS Cluster: InvalidParameterException: 
Compute config is not supported for Kubernetes version 1.28
```

**Solution:**
```hcl
# In terraform.tfvars, ensure:
kubernetes_version = "1.33"  # Must be 1.29 or higher
```

#### Issue: Insufficient IAM Permissions

**Error:**
```
Error: error creating EKS Cluster: AccessDeniedException
```

**Solution:**

Verify you have the appropriate IAM permissions.

- [AWS Troubleshooting IAM Guide](https://docs.aws.amazon.com/IAM/latest/UserGuide/troubleshoot.html)
- [AWS IAM Policy Simulator](https://docs.aws.amazon.com/IAM/latest/UserGuide/access_policies_testing-policies.html)

#### Issue: VPC CIDR Conflicts

**Error:**
```
Error: error creating VPC: VpcAlreadyExists: The VPC with CIDR block 10.0.0.0/16 already exists.

```

**Solution:**
```bash
# Check existing VPCs
aws ec2 describe-vpcs --query 'Vpcs[].CidrBlock'

# Use different CIDR in terraform.tfvars
vpc_cidr = "10.1.0.0/16"  # Avoid conflicts
```

### 4. Pods Not Starting

#### Issue: Pods Pending with Auto Mode

**Symptoms:**
```
NAME                      READY   STATUS    RESTARTS   AGE
openemr-7d8b9c6f5-x2klm   0/1     Pending   0          10m
```

**Diagnosis:**
```bash
# Check pod events
kubectl describe pod openemr-7d8b9c6f5-x2klm -n openemr

# Common Auto Mode events:
# "pod didn't match Pod Security Standards"
# "Insufficient cpu"
# "node(s) had volume node affinity conflict"
```

**Solutions:**

**1. Pod Security Standards Issue:**
See [deployment.yaml](../k8s/deployment.yaml) for correct configurations.
```yaml
# Update pod spec with correct configuration
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
```

**2. Resource Requests Too High:**
```yaml
# Auto Mode has instance type limits
# Adjust resource requests
resources:
  requests:
    cpu: 500m     # Reduced from 2000m
    memory: 1Gi   # Reduced from 4Gi
  limits:
    cpu: 2000m
    memory: 2Gi
```

**3. Storage Issues with EFS:**
```bash
# Validate EFS CSI driver
cd scripts
./validate-efs-csi.sh

# Common fix - restart EFS CSI controller
kubectl rollout restart deployment efs-csi-controller -n kube-system
kubectl rollout status deployment efs-csi-controller -n kube-system

# Check PVC binding
kubectl get pvc -n openemr
```

### 5. Database Connection Issues

#### Symptoms
```
Database connection failed
SQLSTATE[HY000] [2002] Connection refused
ERROR 1045 (28000): Access denied for user 'openemr'@'10.0.1.23'
```

#### Diagnosis
```bash
# Check Aurora cluster status
aws rds describe-db-clusters \
  --db-cluster-identifier openemr-eks-aurora \
  --query 'DBClusters[0].Status'

# Check endpoints
aws rds describe-db-clusters \
  --db-cluster-identifier openemr-eks-aurora \
  --query 'DBClusters[0].Endpoint'

# Test connectivity from pod
kubectl exec -it deployment/openemr -n openemr -- /bin/sh
```

#### Solutions

**1. Security Group Issue:**
```bash
# Get Aurora security group
SG_ID=$(aws rds describe-db-clusters \
  --db-cluster-identifier openemr-eks-aurora \
  --query 'DBClusters[0].VpcSecurityGroups[0].VpcSecurityGroupId' \
  --output text)

# Add EKS nodes to security group
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 3306 \
  --source-group <eks-node-security-group>
```

**2. Wrong Password in Secret:**
```bash
# Get correct password from Terraform
cd terraform
terraform output -raw aurora_password

# Update Kubernetes secret
kubectl create secret generic openemr-db-credentials \
  --namespace=openemr \
  --from-literal=mysql-password="<correct-password>" \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart OpenEMR pods
kubectl rollout restart deployment openemr -n openemr
```

### 6. EKS Auto Mode Specific Issues

#### Issue: Nodes Not Provisioning

**Symptoms:**
```
Pods remain pending
No nodes visible with kubectl get nodes
```

**Diagnosis:**
```bash
# Check Auto Mode events
kubectl get events --all-namespaces | grep -i "auto-mode"

# Check compute configuration
aws eks describe-cluster --name openemr-eks \
  --query 'cluster.computeConfig'

# Verify service quotas
# See documentation: https://docs.aws.amazon.com/servicequotas/latest/userguide/gs-request-quota.html
```

**Solutions:**

**1. Enable Auto Mode (if not enabled):**
```bash
aws eks update-cluster-config \
  --name openemr-eks \
  --compute-config enabled=true \
  --kubernetes-network-config '{"elasticLoadBalancing":{"enabled":true}}' \
  --storage-config '{"blockStorage":{"enabled":true}}'
```

**2. Raise Service Quotas (if necessary):**

See documentation [here](https://docs.aws.amazon.com/servicequotas/latest/userguide/request-quota-increase.html).

#### Issue: 21-Day Node Rotation Disruption

**Symptoms:**
```
Pods restarting every 21 days
Brief service interruptions
```

**Solution:**
```yaml
# Configure Pod Disruption Budget
# NOTE: This is already done for you by default in the deployment.
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: openemr-pdb
  namespace: openemr
spec:
  minAvailable: 1  # Always keep 1 pod running
  selector:
    matchLabels:
      app: openemr
```

## 📊 Common Error Messages Reference

| Error Message | Likely Cause | Solution |
|--------------|-------------|----------|
| `dial tcp: i/o timeout` | IP address changed | Update cluster access with new IP |
| `Pending 0/0 nodes are available` | Auto Mode provisioning | Wait 2-3 minutes for node provisioning |
| `pod didn't match Pod Security Standards` | Security context missing | Add proper securityContext |
| `InvalidParameterException: Compute config` | Wrong K8s version | Use version 1.29+ |
| `SQLSTATE[HY000] [2002]` | Database connection | Check security groups |
| `EFS mount timeout` | EFS CSI issue | Restart EFS CSI controller |
| `403 Forbidden` | IAM permissions | Check pod service account |
| `OOMKilled` | Memory limit exceeded | Increase memory limits |
| `CrashLoopBackOff` | Application startup failure | Check pod logs |
| `ImagePullBackOff` | Can't pull container image | Check image name/registry |

## 💰 Cost and Performance Issues

### Unexpected High Costs

#### Diagnosis
```bash
# Check Auto Mode compute costs (change time range to be one of interest)
aws ce get-cost-and-usage \
  --time-period Start=2025-01-01,End=2025-01-31 \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --filter '{
    "Dimensions": {
      "Key": "SERVICE",
      "Values": ["Amazon Elastic Container Service for Kubernetes"]
    }
  }'

# Check Aurora Serverless usage (change time range to be one of interest)
aws cloudwatch get-metric-statistics \
  --namespace AWS/RDS \
  --metric-name ServerlessDatabaseCapacity \
  --dimensions Name=DBClusterIdentifier,Value=openemr-eks-aurora \
  --start-time 2025-01-01T00:00:00Z \
  --end-time 2025-01-31T23:59:59Z \
  --period 3600 \
  --statistics Average
```

#### Solutions

**1. Right-size Pod Resources:**
```bash
# Check actual vs requested

# Update if over-provisioned
kubectl patch deployment openemr -n openemr -p '{
  "spec": {
    "template": {
      "spec": {
        "containers": [{
          "name": "openemr",
          "resources": {
            "requests": {"cpu": "250m", "memory": "512Mi"},
            "limits": {"cpu": "1000m", "memory": "1Gi"}
          }
        }]
      }
    }
  }
}'
```

**2. Optimize Aurora Serverless:**
```bash
# Reduce minimum ACUs if appropriate
aws rds modify-db-cluster \
  --db-cluster-identifier openemr-eks-aurora \
  --serverless-v2-scaling-configuration MinCapacity=0.5,MaxCapacity=8
```

### Performance Degradation

#### Symptoms
- Slow page loads (>3 seconds)
- Database timeout errors
- High CPU/memory usage

#### Diagnosis
```bash
# Check HPA status
kubectl get hpa -n openemr
```

#### Solutions
```bash
# Scale up immediately
kubectl scale deployment openemr --replicas=5 -n openemr

# Make adjustments to the autoscaling configuration
```

For documentation on how to adjust the autoscaling configuration see [here](AUTOSCALING_GUIDE.md).

## 🔒 Security Incident Response

### If You Suspect a Breach

```bash
#!/bin/bash
# Security incident response

# 1. Block public access
aws eks update-cluster-config \
  --name openemr-eks \
  --resources-vpc-config endpointPublicAccess=false,endpointPrivateAccess=true

# 2. Preserve evidence
kubectl get events --all-namespaces > security-events.txt
kubectl get pods -n openemr -o name | xargs -I {} kubectl logs --all-containers --timestamps -n openemr {} >> security-logs.txt

# 3. Check for unauthorized access
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=AssumeRole \
  --max-items 100

# 4. Totally isolate the cluster.

## Get the cluster security group (the SG attached to the control-plane ENIs)
CLUSTER_SG=$(aws eks describe-cluster --name openemr-eks \
  --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)

## Remove ALL inbound rules
aws ec2 revoke-security-group-ingress \
  --group-id "$CLUSTER_SG" \
  --ip-permissions "$(aws ec2 describe-security-groups --group-ids "$CLUSTER_SG" \
    --query 'SecurityGroups[0].IpPermissions' --output json)"

## (Optional) Remove ALL egress rules too
aws ec2 revoke-security-group-egress \
  --group-id "$CLUSTER_SG" \
  --ip-permissions "$(aws ec2 describe-security-groups --group-ids "$CLUSTER_SG" \
    --query 'SecurityGroups[0].IpPermissionsEgress' --output json)"

# 5. Rotate all credentials

# 6. Notify compliance officer
```

## 🎯 Best Practices for Error Prevention

### Daily Health Checks

```bash
#!/bin/bash
# Daily health check script

echo "=== Daily OpenEMR Health Check ==="
date

# Check cluster
echo "Cluster Status:"
kubectl get nodes

# Check pods
echo "OpenEMR Pods:"
kubectl get pods -n openemr

# Check HPA
echo "Autoscaling Status:"
kubectl get hpa -n openemr

# Check storage
echo "Storage Status:"
kubectl get pvc -n openemr

# Check recent errors
echo "Recent Errors (last hour):"
kubectl logs -n openemr -l app=openemr --since=1h | grep ERROR | tail -5
```

### Weekly Maintenance

```bash

# 1. Update container images, add-ons and other components (if new versions available; test in a development environment before doing any upgrades to production)

# 2. Review and optimize HPA settings

# 3. Check for security updates
aws eks describe-addon-versions --kubernetes-version 1.33 \
  --query 'addons[].{AddonName:addonName,LatestVersion:addonVersions[0].addonVersion}'
```

## 📞 Getting Help

### Before Asking for Help

1. **Run validation scripts**
   ```bash
   cd scripts
   ./validate-deployment.sh
   ./validate-efs-csi.sh
   ```

2. **Document the issue**
   - What were you trying to do?
   - What error did you see?
   - What changed recently?
   - Include relevant logs

### Support Channels

- **[OpenEMR Community Support Section:](https://community.open-emr.org/c/support/16)** For OpenEMR specific support questions.
- **[AWS Support:](https://aws.amazon.com/contact-us/)** For AWS specific support questions.
- **[GitHub Issues for This Project:](../../../issues)** For issues specific to this deployment/project.
