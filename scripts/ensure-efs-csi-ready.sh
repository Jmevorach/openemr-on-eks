#!/usr/bin/env bash
# Restart EFS CSI controller/node so they pick up EKS Pod Identity credentials.
#
# Terraform applies the aws-efs-csi-driver add-on before the Pod Identity
# association is created. Controller pods that start in that window cannot
# provision EFS access points (IMDS / no credentials errors). Rolling the
# deployment after Pod Identity exists fixes provisioning for new PVCs.

set -euo pipefail

EFS_CSI_TIMEOUT="${EFS_CSI_TIMEOUT:-120}"
EFS_CSI_READY_DELAY="${EFS_CSI_READY_DELAY:-10}"

if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "kubectl is not configured; skipping EFS CSI restart" >&2
    exit 1
fi

echo "Restarting EFS CSI driver (Pod Identity may have been wired after add-on install)..."
kubectl rollout restart daemonset/efs-csi-node -n kube-system
kubectl rollout restart deployment/efs-csi-controller -n kube-system

kubectl rollout status daemonset/efs-csi-node -n kube-system --timeout="${EFS_CSI_TIMEOUT}s"
kubectl rollout status deployment/efs-csi-controller -n kube-system --timeout="${EFS_CSI_TIMEOUT}s"

sleep "$EFS_CSI_READY_DELAY"
echo "EFS CSI driver ready."
