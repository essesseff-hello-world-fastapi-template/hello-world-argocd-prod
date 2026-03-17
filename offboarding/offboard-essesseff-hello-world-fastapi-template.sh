#!/bin/bash
set -e

# Templated variables - replaced at onboarding
NAMESPACE="{{K8S_NAMESPACE}}"

echo "=========================================="
echo "⚠️  NAMESPACE OFFBOARDING WARNING ⚠️"
echo "=========================================="
echo "This will DELETE the entire namespace: ${NAMESPACE}"
echo "All resources in this namespace will be permanently removed."
echo ""
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Offboarding cancelled."
    exit 0
fi

echo ""
echo "Starting namespace offboarding..."

# Remove API Gateway key for this namespace (namespace-specific)
kubectl patch secret argocd-notifications-secret -n argocd --type=json \
    -p="[{'op': 'remove', 'path': '/data/aws-api-gateway-key-${NAMESPACE}'}]" \
    2>/dev/null && echo "  ✓ Removed 'aws-api-gateway-key-${NAMESPACE}'" \
    || echo "  ⚠ 'aws-api-gateway-key-${NAMESPACE}' not found or already removed"

# Clean up GHCR credentials
if kubectl get secret ghcr-credentials -n ${NAMESPACE} &>/dev/null; then
    kubectl delete secret ghcr-credentials -n ${NAMESPACE}
    echo "✓ Deleted secret 'ghcr-credentials' from namespace ${NAMESPACE}"
else
    echo "⚠ Secret 'ghcr-credentials' not found in namespace ${NAMESPACE}"
fi


# List resources before deletion for audit trail
echo ""
echo "Resources to be deleted in namespace ${NAMESPACE}:"
kubectl api-resources --verbs=list --namespaced -o name | \
    xargs -n 1 kubectl get --show-kind --ignore-not-found -n ${NAMESPACE} 2>/dev/null || true

echo ""
echo "Deleting namespace ${NAMESPACE}..."
kubectl delete namespace ${NAMESPACE} --ignore-not-found=true --wait=false

# Monitor namespace deletion
echo "Waiting for namespace deletion (timeout: 5 minutes)..."
TIMEOUT=300
ELAPSED=0
while kubectl get namespace ${NAMESPACE} &>/dev/null; do
    if [ $ELAPSED -ge $TIMEOUT ]; then
        echo ""
        echo "⚠️  Namespace deletion is taking longer than expected."
        echo "Checking for stuck resources..."
        
        # Check for resources with finalizers
        kubectl api-resources --verbs=list --namespaced -o name | \
            xargs -n 1 kubectl get --show-kind --ignore-not-found -n ${NAMESPACE} \
            -o jsonpath='{range .items[*]}{.kind}/{.metadata.name}{"\t"}{.metadata.finalizers}{"\n"}{end}' 2>/dev/null | \
            grep -v "^$" || true
        
        echo ""
        read -p "Force remove finalizers from stuck resources? (yes/no): " FORCE_CONFIRM
        
        if [ "$FORCE_CONFIRM" = "yes" ]; then
            echo "Force-removing finalizers..."
            
            # Remove finalizers from common resource types
            for RESOURCE_TYPE in deployment statefulset daemonset service ingress configmap secret pvc; do
                kubectl get ${RESOURCE_TYPE} -n ${NAMESPACE} -o json 2>/dev/null | \
                    jq -r '.items[] | .metadata.name' | \
                    xargs -I {} kubectl patch ${RESOURCE_TYPE} {} -n ${NAMESPACE} \
                    -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
            done
            
            # Force delete the namespace
            kubectl delete namespace ${NAMESPACE} --force --grace-period=0 2>/dev/null || true
        fi
        break
    fi
    
    echo -n "."
    sleep 5
    ELAPSED=$((ELAPSED + 5))
done

echo ""
if ! kubectl get namespace ${NAMESPACE} &>/dev/null; then
    echo ""
    echo "=========================================="
    echo "✓ Namespace offboarding complete"
    echo "=========================================="
    echo "Namespace '${NAMESPACE}' has been removed."
else
    echo ""
    echo "=========================================="
    echo "⚠️  Namespace still exists"
    echo "=========================================="
    echo "Manual intervention may be required."
    echo "Check for stuck resources with:"
    echo "  kubectl get all -n ${NAMESPACE}"
    echo "  kubectl describe namespace ${NAMESPACE}"
fi
