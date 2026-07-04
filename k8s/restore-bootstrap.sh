#!/usr/bin/env bash
# Bootstrap Kubernetes resources required for restore (namespace, storage, IRSA)
# without deploying OpenEMR. Used by inverted restore flow before data Job runs.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="$PROJECT_ROOT/terraform"
NAMESPACE="${NAMESPACE:-openemr}"
AWS_REGION="${AWS_REGION:-us-west-2}"
CLUSTER_NAME="${CLUSTER_NAME:-openemr-eks}"

cd "$PROJECT_ROOT/terraform"
EFS_ID=$(terraform output -raw efs_id)
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
OPENEMR_ROLE_ARN=$(terraform output -raw openemr_role_arn 2>/dev/null || echo "")

cd "$PROJECT_ROOT/k8s"

# Restore .bak files if present from prior deploy runs
for f in *.bak; do
  [ -f "$f" ] || continue
  base="${f%.bak}"
  cp "$f" "$base"
done

sed -i.bak "s/\${EFS_ID}/$EFS_ID/g" storage.yaml
sed -i.bak "s/\${AWS_ACCOUNT_ID}/$AWS_ACCOUNT_ID/g" security.yaml deployment.yaml 2>/dev/null || true
if [ -n "$OPENEMR_ROLE_ARN" ]; then
  sed -i.bak "s|\${OPENEMR_ROLE_ARN}|$OPENEMR_ROLE_ARN|g" security.yaml
fi

# Pod Identity for efs-csi-controller-sa is created after the EKS add-on during
# terraform apply; restart so access-point provisioning works before PVC bind.
"$PROJECT_ROOT/scripts/ensure-efs-csi-ready.sh"

kubectl apply -f namespace.yaml
kubectl apply -f storage.yaml
kubectl apply -f security.yaml

echo "Restore bootstrap complete (namespace, storage, IRSA)"
