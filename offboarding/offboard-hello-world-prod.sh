#!/bin/bash
set -e

# Templated variables - replaced at onboarding
APP_NAME="hello-world"
NAMESPACE="{{K8S_NAMESPACE}}"
ENV="prod"
GITHUB_REPO_ID="{{REPOSITORY_ID}}"

# Argo CD application names
APP_OF_APPS="${APP_NAME}-argocd-${ENV}"
CHILD_APP="${APP_NAME}-${ENV}"

echo "=========================================="
echo "Offboarding Options for: ${APP_NAME}-${ENV}"
echo "Namespace: ${NAMESPACE}"
echo "GitHub Repo ID: ${GITHUB_REPO_ID}"
echo "=========================================="
echo ""
echo "Please select an offboarding mode:"
echo ""
echo "  1) Notifications Only - Sever Argo CD Notifications integrations (essesseff)"
echo "     • Removes webhook service and subscription"
echo "     • Removes notification secrets"
echo "     • Preserves Argo CD applications and Kubernetes resources"
echo "     • Use this when switching away from essesseff but keeping the deployment"
echo ""
echo "  2) Full Offboarding - Complete removal from Argo CD and Kubernetes"
echo "     • Deletes Argo CD applications (app-of-apps and child)"
echo "     • Removes all Kubernetes resources in namespace"
echo "     • Removes Argo CD repository secrets"
echo "     • Removes notification integrations"
echo "     • Use this for complete deployment removal"
echo ""
read -p "Enter your choice (1 or 2): " -n 1 -r MODE
echo ""
echo ""

if [[ ! $MODE =~ ^[12]$ ]]; then
  echo "❌ Invalid selection. Please run the script again and choose 1 or 2."
  exit 1
fi

if [ "$MODE" = "1" ]; then
  echo "=========================================="
  echo "Mode: Notifications Only Cleanup"
  echo "=========================================="
  echo ""
  echo "This will:"
  echo "  • Remove Argo CD Notifications webhook service for repo ${GITHUB_REPO_ID}"
  echo "  • Remove webhook subscription for repo ${GITHUB_REPO_ID}"
  echo "  • Remove app-specific notification secrets"
  echo "  • Restart notifications controller"
  echo ""
  echo "This will NOT:"
  echo "  • Delete Argo CD applications"
  echo "  • Remove Kubernetes resources"
  echo "  • Remove repository secrets"
  echo ""
  read -p "Continue with notifications cleanup? (y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted"
    exit 1
  fi
  
  # Clean up Argo CD Notifications ConfigMap entries
  echo ""
  echo "Cleaning up Argo CD Notifications ConfigMap entries..."

  if kubectl get configmap argocd-notifications-cm -n argocd &>/dev/null; then
    echo "Removing repo-specific webhook service..."
    
    # Remove webhook service for this repository
    kubectl patch configmap argocd-notifications-cm -n argocd --type=json \
        -p="[{'op': 'remove', 'path': '/data/service.webhook.webhook-${GITHUB_REPO_ID}'}]" \
        2>/dev/null && echo "  ✓ Removed service.webhook.webhook-${GITHUB_REPO_ID}" \
        || echo "  ⚠ service.webhook.webhook-${GITHUB_REPO_ID} not found or already removed"
    
    # Remove subscription for this repository
    echo "Removing webhook subscription for configenvrepoid=${GITHUB_REPO_ID}..."
    
    # Get current subscriptions
    CURRENT_SUBSCRIPTIONS=$(kubectl get configmap argocd-notifications-cm -n argocd -o jsonpath='{.data.subscriptions}' 2>/dev/null || echo "")
    
    if [ -n "$CURRENT_SUBSCRIPTIONS" ] && [ "$CURRENT_SUBSCRIPTIONS" != "null" ]; then
        # Remove the subscription block for this repository ID using awk
        FILTERED_SUBSCRIPTIONS=$(echo "$CURRENT_SUBSCRIPTIONS" | awk -v webhook="webhook-${GITHUB_REPO_ID}" -v repoid="${GITHUB_REPO_ID}" '
        BEGIN { in_block=0; block="" }
        /^- recipients:/ { 
            if (in_block && block !~ webhook && block !~ ("configenvrepoid=" repoid)) {
                printf "%s", block
            }
            in_block=1
            block=$0 "\n"
            next
        }
        {
            if (in_block) {
                block = block $0 "\n"
            } else {
                print
            }
        }
        END {
            if (in_block && block !~ webhook && block !~ ("configenvrepoid=" repoid)) {
                printf "%s", block
            }
        }')
        
        # Create temporary patch file
        TEMP_PATCH=$(mktemp)
        
        # Escape the YAML content for JSON
        if command -v jq &> /dev/null; then
            ESCAPED_SUBS=$(printf '%s' "$FILTERED_SUBSCRIPTIONS" | jq -Rs . | sed 's/^"//;s/"$//')
        elif command -v python3 &> /dev/null; then
            ESCAPED_SUBS=$(printf '%s' "$FILTERED_SUBSCRIPTIONS" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read())[1:-1])")
        else
            ESCAPED_SUBS=$(printf '%s' "$FILTERED_SUBSCRIPTIONS" | \
                awk 'BEGIN{ORS=""} {gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); if (NR>1) printf "\\n"; printf "%s", $0}')
        fi
        
        cat > "$TEMP_PATCH" <<EOF
{
  "data": {
    "subscriptions": "${ESCAPED_SUBS}"
  }
}
EOF
        
        # Patch the subscriptions field
        kubectl patch configmap argocd-notifications-cm -n argocd \
            --type merge \
            --patch-file "$TEMP_PATCH"
        
        # Clean up
        rm -f "$TEMP_PATCH"
        
        echo "  ✓ Removed subscription for 'webhook-${GITHUB_REPO_ID}'"
    else
        echo "  ⚠ No subscriptions found in ConfigMap"
    fi
    
    echo "✓ Notification ConfigMap entries cleaned up"
    echo "  Note: Shared templates and triggers are preserved for other apps"
  else
    echo "⚠ argocd-notifications-cm not found in argocd namespace"
  fi

  # Clean up Argo CD Notifications Secret entries
  echo ""
  echo "Cleaning up Argo CD Notifications Secret entries..."

  if kubectl get secret argocd-notifications-secret -n argocd &>/dev/null; then
    echo "Removing repo-specific notification secrets..."
    
    # DO NOT remove argocd-webhook-url - it's shared across all apps
    echo "  ⊘ Preserving shared 'argocd-webhook-url'"
    
    # DO NOT remove aws-api-gateway-key-${NAMESPACE} - it's namespace-scoped, shared across deployments
    echo "  ⊘ Preserving namespace-scoped 'aws-api-gateway-key-${NAMESPACE}'"
    
    # Remove app secret for this repo (repository-specific, deployment-specific)
    kubectl patch secret argocd-notifications-secret -n argocd --type=json \
        -p="[{'op': 'remove', 'path': '/data/app-secret-${GITHUB_REPO_ID}'}]" \
        2>/dev/null && echo "  ✓ Removed 'app-secret-${GITHUB_REPO_ID}'" \
        || echo "  ⚠ 'app-secret-${GITHUB_REPO_ID}' not found or already removed"
    
    echo "✓ Notification Secret entries cleaned up"
  else
    echo "⚠ argocd-notifications-secret not found in argocd namespace"
  fi

  # Restart notification controller to reload configuration
  echo ""
  echo "🔄 Restarting notifications controller to reload configuration..."
  kubectl rollout restart deploy argocd-notifications-controller -n argocd

  echo ""
  echo "=========================================="
  echo "✅ Notifications cleanup complete"
  echo "=========================================="
  echo ""
  echo "Cleaned up:"
  echo "  ✓ Webhook service: webhook-${GITHUB_REPO_ID}"
  echo "  ✓ Webhook subscription for repo ${GITHUB_REPO_ID}"
  echo "  ✓ App secret: app-secret-${GITHUB_REPO_ID}"
  echo ""
  echo "Preserved:"
  echo "  • Argo CD applications: ${APP_OF_APPS}, ${CHILD_APP}"
  echo "  • Kubernetes resources in namespace ${NAMESPACE}"
  echo "  • Argo CD repository secrets"
  echo "  • Webhook URL: argocd-webhook-url"
  echo "  • AWS API Gateway key: aws-api-gateway-key-${NAMESPACE}"
  echo "  • GHCR credentials"
  echo "  • Shared templates and triggers"
  echo ""
  echo "Your deployment continues to run, but essesseff notifications are disabled."

elif [ "$MODE" = "2" ]; then
  echo "=========================================="
  echo "Mode: Full Offboarding"
  echo "=========================================="
  echo ""
  echo "App-of-Apps Pattern:"
  echo "  Parent: ${APP_OF_APPS}"
  echo "  Child:  ${CHILD_APP}"
  echo ""
  echo "This will:"
  echo "  • Delete Argo CD applications (cascading to all resources)"
  echo "  • Remove all Kubernetes resources in namespace"
  echo "  • Remove Argo CD repository secrets"
  echo "  • Remove notification integrations"
  echo ""
  echo "⚠️  WARNING: This is destructive and cannot be undone!"
  echo ""
  read -p "Continue with full offboarding? (y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted"
    exit 1
  fi

  # CRITICAL: Add cascade deletion finalizer to parent app-of-apps
  echo ""
  echo "Adding cascade deletion finalizer to parent application..."
  if kubectl get application ${APP_OF_APPS} -n argocd &>/dev/null; then
      kubectl patch application ${APP_OF_APPS} -n argocd \
          -p '{"metadata":{"finalizers":["resources-finalizer.argocd.argoproj.io"]}}' \
          --type merge
      echo "✓ Finalizer added to ${APP_OF_APPS}"
  else
      echo "⚠ Parent application ${APP_OF_APPS} not found"
  fi

  # CRITICAL: Add cascade deletion finalizer to child application (in case it exists independently)
  echo "Adding cascade deletion finalizer to child application..."
  if kubectl get application ${CHILD_APP} -n argocd &>/dev/null; then
      kubectl patch application ${CHILD_APP} -n argocd \
          -p '{"metadata":{"finalizers":["resources-finalizer.argocd.argoproj.io"]}}' \
          --type merge
      echo "✓ Finalizer added to ${CHILD_APP}"
  else
      echo "⚠ Child application ${CHILD_APP} not found (may be managed by parent)"
  fi

  echo ""
  echo "⏳ Finalizers configured. Now deleting applications..."
  echo "This will trigger Argo CD to delete all managed Kubernetes resources."
  echo ""

  # Delete the parent Argo CD Application (app-of-apps)
  # With the finalizer in place, this will cascade delete all managed resources
  echo "Deleting parent Argo CD Application (app-of-apps): ${APP_OF_APPS}..."
  if kubectl get application ${APP_OF_APPS} -n argocd &>/dev/null; then
      kubectl delete application ${APP_OF_APPS} -n argocd
      echo "✓ Parent application ${APP_OF_APPS} deletion initiated"
      
      # Wait for parent to be removed (this may take time as resources are being cleaned up)
      echo "⏳ Waiting for Argo CD to delete all managed resources (this may take several minutes)..."
      kubectl wait --for=delete application/${APP_OF_APPS} -n argocd --timeout=600s || true
      echo "✓ Parent application deleted"
  else
      echo "⚠ Parent application ${APP_OF_APPS} not found (may already be deleted)"
  fi

  # Check if child application still exists and delete it if necessary
  echo ""
  echo "Checking child application status..."
  sleep 5  # Give Argo CD a moment to cascade delete

  if kubectl get application ${CHILD_APP} -n argocd &>/dev/null; then
      echo "⚠ Child application ${CHILD_APP} still exists, deleting explicitly..."
      kubectl delete application ${CHILD_APP} -n argocd
      kubectl wait --for=delete application/${CHILD_APP} -n argocd --timeout=600s || true
      echo "✓ Child application ${CHILD_APP} deleted"
  else
      echo "✓ Child application ${CHILD_APP} automatically removed by parent deletion"
  fi

  # Wait for Argo CD to finish cleaning up managed resources
  echo ""
  echo "⏳ Waiting for resource cleanup to complete..."
  sleep 15

  # Verify all managed resources are actually removed from the namespace
  echo ""
  echo "Verifying resource cleanup in namespace ${NAMESPACE}..."

  # Check for any remaining resources by name pattern (most reliable)
  REMAINING_DEPLOYMENTS=$(kubectl get deployments -n ${NAMESPACE} ${CHILD_APP} --ignore-not-found --no-headers 2>/dev/null | wc -l)
  REMAINING_SERVICES=$(kubectl get services -n ${NAMESPACE} ${CHILD_APP} --ignore-not-found --no-headers 2>/dev/null | wc -l)
  REMAINING_INGRESS=$(kubectl get ingress -n ${NAMESPACE} ${CHILD_APP} --ignore-not-found --no-headers 2>/dev/null | wc -l)
  REMAINING_CONFIGMAPS=$(kubectl get configmaps -n ${NAMESPACE} ${CHILD_APP} --ignore-not-found --no-headers 2>/dev/null | wc -l)
  REMAINING_REPLICASETS=$(kubectl get replicasets -n ${NAMESPACE} -l app=${APP_NAME} --no-headers 2>/dev/null | wc -l)
  REMAINING_PODS=$(kubectl get pods -n ${NAMESPACE} -l app=${APP_NAME} --no-headers 2>/dev/null | wc -l)

  # Also check for secrets by name pattern
  REMAINING_SECRETS=0
  for secret_type in "" "-secret" "-config" "-tls"; do
      if kubectl get secret ${CHILD_APP}${secret_type} -n ${NAMESPACE} --ignore-not-found &>/dev/null; then
          REMAINING_SECRETS=$((REMAINING_SECRETS + 1))
      fi
  done

  TOTAL_REMAINING=$((REMAINING_DEPLOYMENTS + REMAINING_SERVICES + REMAINING_INGRESS + REMAINING_CONFIGMAPS + REMAINING_SECRETS + REMAINING_REPLICASETS + REMAINING_PODS))

  if [ "$TOTAL_REMAINING" -eq 0 ]; then
      echo "✓ All managed resources cleaned up successfully by Argo CD"
  else
      echo "⚠ Some resources still remain after Argo CD cleanup:"
      echo "  - Deployments: ${REMAINING_DEPLOYMENTS}"
      echo "  - ReplicaSets: ${REMAINING_REPLICASETS}"
      echo "  - Pods: ${REMAINING_PODS}"
      echo "  - Services: ${REMAINING_SERVICES}"
      echo "  - Ingress: ${REMAINING_INGRESS}"
      echo "  - ConfigMaps: ${REMAINING_CONFIGMAPS}"
      echo "  - Secrets: ${REMAINING_SECRETS}"
      echo ""
      echo "Attempting manual cleanup of remaining resources..."
      
      # Strategy 1: Delete by resource name (most reliable)
      kubectl delete deployment ${CHILD_APP} -n ${NAMESPACE} --ignore-not-found=true
      kubectl delete service ${CHILD_APP} -n ${NAMESPACE} --ignore-not-found=true
      kubectl delete ingress ${CHILD_APP} -n ${NAMESPACE} --ignore-not-found=true
      kubectl delete configmap ${CHILD_APP} -n ${NAMESPACE} --ignore-not-found=true
      
      # Strategy 2: Delete by label (in case resources use app label)
      kubectl delete deployment -n ${NAMESPACE} -l app=${APP_NAME} --ignore-not-found=true
      kubectl delete service -n ${NAMESPACE} -l app=${APP_NAME} --ignore-not-found=true
      kubectl delete ingress -n ${NAMESPACE} -l app=${APP_NAME} --ignore-not-found=true
      kubectl delete configmap -n ${NAMESPACE} -l app=${APP_NAME} --ignore-not-found=true
      kubectl delete secret -n ${NAMESPACE} -l app=${APP_NAME} --ignore-not-found=true
      kubectl delete replicaset -n ${NAMESPACE} -l app=${APP_NAME} --ignore-not-found=true
      kubectl delete pod -n ${NAMESPACE} -l app=${APP_NAME} --ignore-not-found=true --force --grace-period=0
      
      # Strategy 3: Common secret name patterns
      kubectl delete secret ${CHILD_APP}-secret -n ${NAMESPACE} --ignore-not-found=true
      kubectl delete secret ${CHILD_APP}-config -n ${NAMESPACE} --ignore-not-found=true
      kubectl delete secret ${CHILD_APP}-tls -n ${NAMESPACE} --ignore-not-found=true
      
      echo "✓ Manual cleanup completed"
  fi

  # Clean up Argo CD repository secrets
  echo ""
  echo "Cleaning up Argo CD repository secrets..."

  # Delete argocd repo secret
  if kubectl get secret ${APP_NAME}-argocd-${ENV}-repo -n argocd &>/dev/null; then
      kubectl delete secret ${APP_NAME}-argocd-${ENV}-repo -n argocd
      echo "✓ Deleted secret '${APP_NAME}-argocd-${ENV}-repo'"
  else
      echo "⚠ Secret '${APP_NAME}-argocd-${ENV}-repo' not found"
  fi

  # Delete config repo secret
  if kubectl get secret ${APP_NAME}-config-${ENV}-repo -n argocd &>/dev/null; then
      kubectl delete secret ${APP_NAME}-config-${ENV}-repo -n argocd
      echo "✓ Deleted secret '${APP_NAME}-config-${ENV}-repo'"
  else
      echo "⚠ Secret '${APP_NAME}-config-${ENV}-repo' not found"
  fi

  # Clean up Argo CD Notifications ConfigMap entries
  echo ""
  echo "Cleaning up Argo CD Notifications ConfigMap entries..."

  if kubectl get configmap argocd-notifications-cm -n argocd &>/dev/null; then
      echo "Removing repo-specific webhook service..."
      
      # Remove webhook service for this repository
      kubectl patch configmap argocd-notifications-cm -n argocd --type=json \
          -p="[{'op': 'remove', 'path': '/data/service.webhook.webhook-${GITHUB_REPO_ID}'}]" \
          2>/dev/null && echo "  ✓ Removed service.webhook.webhook-${GITHUB_REPO_ID}" \
          || echo "  ⚠ service.webhook.webhook-${GITHUB_REPO_ID} not found or already removed"
      
      # Remove subscription for this repository
      echo "Removing webhook subscription for configenvrepoid=${GITHUB_REPO_ID}..."
      
      # Get current subscriptions
      CURRENT_SUBSCRIPTIONS=$(kubectl get configmap argocd-notifications-cm -n argocd -o jsonpath='{.data.subscriptions}' 2>/dev/null || echo "")
      
      if [ -n "$CURRENT_SUBSCRIPTIONS" ] && [ "$CURRENT_SUBSCRIPTIONS" != "null" ]; then
          # Remove the subscription block for this repository ID using awk
          FILTERED_SUBSCRIPTIONS=$(echo "$CURRENT_SUBSCRIPTIONS" | awk -v webhook="webhook-${GITHUB_REPO_ID}" -v repoid="${GITHUB_REPO_ID}" '
          BEGIN { in_block=0; block="" }
          /^- recipients:/ { 
              if (in_block && block !~ webhook && block !~ ("configenvrepoid=" repoid)) {
                  printf "%s", block
              }
              in_block=1
              block=$0 "\n"
              next
          }
          {
              if (in_block) {
                  block = block $0 "\n"
              } else {
                  print
              }
          }
          END {
              if (in_block && block !~ webhook && block !~ ("configenvrepoid=" repoid)) {
                  printf "%s", block
              }
          }')
          
          # Create temporary patch file
          TEMP_PATCH=$(mktemp)
          
          # Escape the YAML content for JSON
          if command -v jq &> /dev/null; then
              ESCAPED_SUBS=$(printf '%s' "$FILTERED_SUBSCRIPTIONS" | jq -Rs . | sed 's/^"//;s/"$//')
          elif command -v python3 &> /dev/null; then
              ESCAPED_SUBS=$(printf '%s' "$FILTERED_SUBSCRIPTIONS" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read())[1:-1])")
          else
              ESCAPED_SUBS=$(printf '%s' "$FILTERED_SUBSCRIPTIONS" | \
                  awk 'BEGIN{ORS=""} {gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); if (NR>1) printf "\\n"; printf "%s", $0}')
          fi
          
          cat > "$TEMP_PATCH" <<EOF
{
  "data": {
    "subscriptions": "${ESCAPED_SUBS}"
  }
}
EOF
          
          # Patch the subscriptions field
          kubectl patch configmap argocd-notifications-cm -n argocd \
              --type merge \
              --patch-file "$TEMP_PATCH"
          
          # Clean up
          rm -f "$TEMP_PATCH"
          
          echo "  ✓ Removed subscription for 'webhook-${GITHUB_REPO_ID}'"
      else
          echo "  ⚠ No subscriptions found in ConfigMap"
      fi
      
      echo "✓ Notification ConfigMap entries cleaned up"
      echo "  Note: Shared templates and triggers are preserved for other apps"
  else
      echo "⚠ argocd-notifications-cm not found in argocd namespace"
  fi

  # Clean up Argo CD Notifications Secret entries
  echo ""
  echo "Cleaning up Argo CD Notifications Secret entries..."

  if kubectl get secret argocd-notifications-secret -n argocd &>/dev/null; then
      echo "Removing repo-specific notification secrets..."
      
      # DO NOT remove argocd-webhook-url - it's shared across all apps
      echo "  ⊘ Preserving shared 'argocd-webhook-url'"
      
      # DO NOT remove aws-api-gateway-key-${NAMESPACE} - it's namespace-scoped, shared across deployments
      echo "  ⊘ Preserving namespace-scoped 'aws-api-gateway-key-${NAMESPACE}'"
      
      # Remove app secret for this repo (repository-specific, deployment-specific)
      kubectl patch secret argocd-notifications-secret -n argocd --type=json \
          -p="[{'op': 'remove', 'path': '/data/app-secret-${GITHUB_REPO_ID}'}]" \
          2>/dev/null && echo "  ✓ Removed 'app-secret-${GITHUB_REPO_ID}'" \
          || echo "  ⚠ 'app-secret-${GITHUB_REPO_ID}' not found or already removed"
      
      echo "✓ Notification Secret entries cleaned up"
  else
      echo "⚠ argocd-notifications-secret not found in argocd namespace"
  fi

  # Restart notification controller to reload configuration
  echo ""
  echo "🔄 Restarting notifications controller to reload configuration..."
  kubectl rollout restart deploy argocd-notifications-controller -n argocd

  echo ""
  echo "=========================================="
  echo "✅ Full offboarding complete"
  echo "=========================================="
  echo ""
  echo "Cleaned up:"
  echo "  ✓ Argo CD App-of-Apps: ${APP_OF_APPS}"
  echo "  ✓ Argo CD Child Application: ${CHILD_APP}"
  echo "  ✓ All Kubernetes resources managed by Argo CD in namespace ${NAMESPACE}"
  echo "  ✓ Argo CD repository secrets: ${APP_NAME}-argocd-${ENV}-repo, ${APP_NAME}-config-${ENV}-repo"
  echo "  ✓ Webhook service: webhook-${GITHUB_REPO_ID}"
  echo "  ✓ Webhook subscription for repo ${GITHUB_REPO_ID}"
  echo "  ✓ App secret: app-secret-${GITHUB_REPO_ID}"
  echo ""
  echo "Preserved (shared across apps/deployments):"
  echo "  • Webhook URL: argocd-webhook-url"
  echo "  • AWS API Gateway key: aws-api-gateway-key-${NAMESPACE} (namespace-scoped)"
  echo "  • GHCR credentials in namespace ${NAMESPACE} (namespace-scoped)"
  echo "  • Template: app-sync-status"
  echo "  • Triggers: on-sync-started, on-sync-succeeded, on-sync-failed, on-deployed, on-health-degraded"
  echo ""
  echo "Note: Namespace '${NAMESPACE}' still exists."
  echo "To remove the entire namespace and all namespace-scoped resources, run: ./offboard-namespace.sh"
fi
