#!/bin/bash

# setup-argocd.sh

# Setup Argo CD for ${APP_NAME} staging

# This script sets up Argo CD notifications for an essesseff app as well as the Argo CD deployment
# configuration for the app.
# Template variables (${APP_NAME}, essesseff-hello-world-fastapi-template, {{REPOSITORY_ID}}, etc.) 
# are replaced when apps are created from templates.

set -e

# Override these if they're set in .env, otherwise use defaults
APP_NAME="hello-world"
GITHUB_ORG="essesseff-hello-world-fastapi-template"
ENVIRONMENT="prod"
REPOSITORY_ID="{{REPOSITORY_ID}}"

# ============================================================================
# Load environment variables from .env file
# ============================================================================
if [ ! -f ".env" ]; then
  echo "❌ Error: .env file not found"
  echo ""
  echo "Please create a .env file with the following variables:"
  echo "  ARGOCD_MACHINE_USER=your-username"
  echo "  GITHUB_TOKEN=your-token"
  echo "  ARGOCD_MACHINE_EMAIL=your-email@example.com"
  echo ""
  echo "See env.example for a template"
  exit 1
fi

echo "📦 Loading environment variables from .env..."
set -a  # automatically export all variables
source .env
set +a

# Generate base64 auth string for GHCR
export GHCR_AUTH_BASE64=$(echo -n "${ARGOCD_MACHINE_USER}:${GITHUB_TOKEN}" | base64 | tr -d '\n')

# ============================================================================
# Generate YAML files from templates
# ============================================================================
echo "📝 Generating YAML files from templates..."

# Check if envsubst is available
if ! command -v envsubst &> /dev/null; then
  echo "❌ Error: envsubst command not found"
  echo "Please install gettext package:"
  echo "  - macOS: brew install gettext && brew link --force gettext"
  echo "  - Ubuntu/Debian: apt-get install gettext-base"
  echo "  - RHEL/CentOS: yum install gettext"
  exit 1
fi

# Generate argocd/${APP_NAME}-${ENVIRONMENT}-application.yaml
if [ -f "argocd/${APP_NAME}-${ENVIRONMENT}-application.yaml.template" ]; then
  envsubst < argocd/${APP_NAME}-${ENVIRONMENT}-application.yaml.template > argocd/${APP_NAME}-${ENVIRONMENT}-application.yaml
  echo "  ✓ Generated updated argocd/${APP_NAME}-${ENVIRONMENT}-application.yaml"
else
  echo "  ⚠️  argocd/${APP_NAME}-${ENVIRONMENT}-application.yaml.template not found"
  exit 1
fi

# Generate app-of-apps.yaml
if [ -f "app-of-apps.yaml.template" ]; then
  envsubst < app-of-apps.yaml.template > app-of-apps.yaml
  echo "  ✓ Generated updated app-of-apps.yaml"
else
  echo "  ⚠️  app-of-apps.yaml.template not found"
  exit 1
fi

# Generate argocd-repository-secret.yaml
if [ -f "argocd-repository-secret.yaml.template" ]; then
  envsubst < argocd-repository-secret.yaml.template > argocd-repository-secret.yaml
  echo "  ✓ Generated updated argocd-repository-secret.yaml"
else
  echo "  ⚠️  argocd-repository-secret.yaml.template not found"
  exit 1
fi

# Generate ghcr-credentials-secret.yaml
if [ -f "ghcr-credentials-secret.yaml.template" ]; then
  envsubst < ghcr-credentials-secret.yaml.template > ghcr-credentials-secret.yaml
  echo "  ✓ Generated updated ghcr-credentials-secret.yaml"
else
  echo "  ⚠️  ghcr-credentials-secret.yaml.template not found... proceeding with the assumption that ghcr-credentials secret value already set"
fi

echo "=========================================="
echo "Setting up Argo CD for ${APP_NAME} ${ENVIRONMENT}"
echo "=========================================="

# Determine if this is an essesseff-subscribed app
# Check if notifications-secret.yaml exists and is not a dummy file
ENABLE_NOTIFICATIONS=false
if [ -f "notifications-secret.yaml" ]; then
  # Check if it's not just a dummy/placeholder file (has meaningful content)
  # A real notifications-secret.yaml should have actual secret data
  if grep -q "stringData:" "notifications-secret.yaml" || grep -q "data:" "notifications-secret.yaml"; then
    ENABLE_NOTIFICATIONS=true
    echo "📢 Detected essesseff app - Argo CD Notifications will be configured"
  else
    echo "ℹ️  Dummy notifications-secret.yaml detected - skipping Argo CD Notifications setup"
  fi
else
  echo "ℹ️  No notifications-secret.yaml found - skipping Argo CD Notifications setup"
fi
echo ""

# Verify Argo CD Notifications catalog is installed (only for essesseff apps)
if [ "$ENABLE_NOTIFICATIONS" = true ]; then
  # This should be installed once per cluster using setup-argocd-cluster.sh
  echo "📦 Verifying Argo CD Notifications catalog installation..."
  if kubectl get configmap argocd-notifications-cm -n argocd &> /dev/null; then
    if kubectl get configmap argocd-notifications-cm -n argocd -o yaml | grep -q "trigger.on-sync-succeeded:"; then
      echo "  ✓ Notifications catalog is installed"
    else
      echo "  ✗ ERROR: ConfigMap exists but catalog triggers not found"
      echo ""
      echo "  The Argo CD Notifications catalog must be installed first."
      echo "  Run: ./setup-argocd-cluster.sh"
      echo "  Or manually: kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/notifications_catalog/install.yaml"
      exit 1
    fi
  else
    echo "  ✗ ERROR: ConfigMap 'argocd-notifications-cm' not found"
    echo ""
    echo "  The Argo CD Notifications catalog must be installed first."
    echo "  Run: ./setup-argocd-cluster.sh"
    echo "  Or manually: kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/notifications_catalog/install.yaml"
    exit 1
  fi
  echo ""
fi

# Check if ghcr-credentials-secret.yaml exists
if [ ! -f "ghcr-credentials-secret.yaml" ]; then
  echo "❌ Error: ghcr-credentials-secret.yaml not found; therefore, ghcr-credentials secret will not be set."
#   echo "Please ensure ghcr-credentials-secret.yaml exists and has the correct secret for ${GITHUB_ORG}"
#   echo ""
#   read -p "Continue anyway (for example, in the case of ghcr-credentials having been previously applied on this K8s cluster)? (y/n) " -n 1 -r
#   echo
#   if [[ ! $REPLY =~ ^[Yy]$ ]]; then
#     echo "Aborted"
#     exit 1
#   fi
fi

# Check if argocd-repository-secret.yaml exists
if [ ! -f "argocd-repository-secret.yaml" ]; then
  echo "❌ Error: argocd-repository-secret.yaml not found"
  echo "Please ensure argocd-repository-secret.yaml exists and has the correct secrets for ${APP_NAME}"
  exit 1
fi

# Check if notifications-configmap.yaml exists (only for essesseff apps)
if [ "$ENABLE_NOTIFICATIONS" = true ]; then
  if [ ! -f "notifications-configmap.yaml" ]; then
    echo "❌ Error: notifications-configmap.yaml not found"
    exit 1
  fi
fi

# Warning about secrets
# echo ""
# if [ "$ENABLE_NOTIFICATIONS" = true ]; then
#   echo "⚠️  WARNING: You are about to apply secrets to your cluster for ${GITHUB_ORG} organization and ${APP_NAME} ${ENVIRONMENT}"
#   echo ""
#   echo "Make sure ghcr-credentials-secret.yaml contains the correct secrets for ${GITHUB_ORG}"
#   echo "Make sure argocd-repository-secret.yaml and notifications-secret.yaml contain the correct secrets for ${APP_NAME}"
# else
#   echo "⚠️  WARNING: You are about to apply secrets to your cluster for ${GITHUB_ORG} organization and ${APP_NAME} ${ENVIRONMENT}"
#   echo ""
#   echo "Make sure ghcr-credentials-secret.yaml contains the correct secrets for ${GITHUB_ORG}"
#   echo "Make sure argocd-repository-secret.yaml contains the correct secrets for ${APP_NAME}"
# fi
# echo ""
# read -p "Continue? (y/n) " -n 1 -r
# echo
# if [[ ! $REPLY =~ ^[Yy]$ ]]; then
#   echo "Aborted"
#   exit 1
# fi

# Apply secrets
if [ -f "ghcr-credentials-secret.yaml" ]; then
  echo ""
  echo "📝 Applying GHCR image pull secrets..."
  kubectl apply -f ghcr-credentials-secret.yaml
fi

echo ""
echo "📝 Applying config repo secrets..."
kubectl apply -f argocd-repository-secret.yaml

# Apply notification secrets and configure notifications (only for essesseff apps)
if [ "$ENABLE_NOTIFICATIONS" = true ]; then
  echo ""
  echo "📝 Applying notification secrets..."
  kubectl apply -f notifications-secret.yaml

  # Patch configmap (merge, don't override)
  # This is safe because we use repository ID-based naming (webhook-{REPOSITORY_ID})
  # which ensures unique keys per app/environment
  echo "📝 Patching notification configmap (merging with existing entries)..."

  # Kubernetes objects (including ConfigMaps) have a practical size limit (~1MiB) due to etcd.
  CONFIGMAP_SIZE_LIMIT_BYTES=$((1024 * 1024))          # 1 MiB
  SUBSCRIPTIONS_SAFETY_BUFFER_BYTES=$((128 * 1024))    # buffer for other ConfigMap keys/metadata
  MAX_SUBSCRIPTIONS_BYTES=$((CONFIGMAP_SIZE_LIMIT_BYTES - SUBSCRIPTIONS_SAFETY_BUFFER_BYTES))

  # Best-effort: estimate final ConfigMap size after merging notifications-configmap.yaml (server-side dry-run)
  echo "  🔎 Estimating ConfigMap size after merge (server-side dry-run)..."
  if DRY_RUN_MERGE_CM_JSON=$(kubectl patch configmap argocd-notifications-cm -n argocd \
    --type merge \
    --patch-file notifications-configmap.yaml \
    --dry-run=server \
    -o json 2>/dev/null); then
    DRY_RUN_MERGE_CM_BYTES=$(printf '%s' "$DRY_RUN_MERGE_CM_JSON" | wc -c | tr -d ' ')
    echo "  ℹ️  Estimated ConfigMap JSON size after merge: ${DRY_RUN_MERGE_CM_BYTES} bytes (limit ~${CONFIGMAP_SIZE_LIMIT_BYTES})"

    if [ "$DRY_RUN_MERGE_CM_BYTES" -gt "$CONFIGMAP_SIZE_LIMIT_BYTES" ]; then
      echo ""
      echo "❌ ERROR: ConfigMap would exceed the Kubernetes/etcd object size limit after merge."
      echo "   Estimated size: ${DRY_RUN_MERGE_CM_BYTES} bytes"
      echo "   Limit:          ${CONFIGMAP_SIZE_LIMIT_BYTES} bytes"
      echo ""
      echo "   Refusing to patch argocd-notifications-cm with notifications-configmap.yaml."
      echo "   Consider reducing the number/size of ConfigMap entries or splitting configuration."
      exit 1
    fi
  else
    echo "  ⚠️  Could not run dry-run size estimation (insufficient permissions or older cluster)."
    echo "     Proceeding without merge-size validation."
  fi

  kubectl patch configmap argocd-notifications-cm -n argocd \
    --type merge \
    --patch-file notifications-configmap.yaml

  # Merge subscriptions field (requires special handling to append, not overwrite)
  echo "📝 Merging subscriptions field (adding webhook-${REPOSITORY_ID} subscription)..."
  WEBHOOK_NAME="webhook-${REPOSITORY_ID}"

  # Get current subscriptions field
  CURRENT_SUBSCRIPTIONS=$(kubectl get configmap argocd-notifications-cm -n argocd -o jsonpath='{.data.subscriptions}' 2>/dev/null || echo "")
  CURRENT_SUBSCRIPTIONS_BYTES=$(printf '%s' "$CURRENT_SUBSCRIPTIONS" | wc -c | tr -d ' ')
  echo "  ℹ️  Current subscriptions size: ${CURRENT_SUBSCRIPTIONS_BYTES} bytes"

  # Check if subscription for this webhook already exists
  if echo "$CURRENT_SUBSCRIPTIONS" | grep -q "webhook-${REPOSITORY_ID}"; then
    echo "  ✓ Subscription for '${WEBHOOK_NAME}' already exists, skipping"
  else
    # Create new subscription entry
    NEW_SUBSCRIPTION="- recipients:
  - ${WEBHOOK_NAME}
  triggers:
  - on-sync-started
  - on-sync-succeeded
  - on-sync-failed
  - on-deployed
  - on-health-degraded
  selector: configenvrepoid=${REPOSITORY_ID}"

    # Merge subscriptions
    if [ -z "$CURRENT_SUBSCRIPTIONS" ] || [ "$CURRENT_SUBSCRIPTIONS" = "null" ]; then
      # No existing subscriptions, create new
      MERGED_SUBSCRIPTIONS="$NEW_SUBSCRIPTION"
    else
      # Append to existing subscriptions
      MERGED_SUBSCRIPTIONS="${CURRENT_SUBSCRIPTIONS}
${NEW_SUBSCRIPTION}"
    fi

    MERGED_SUBSCRIPTIONS_BYTES=$(printf '%s' "$MERGED_SUBSCRIPTIONS" | wc -c | tr -d ' ')
    echo "  ℹ️  New subscriptions size (after append): ${MERGED_SUBSCRIPTIONS_BYTES} bytes"

    if [ "$MERGED_SUBSCRIPTIONS_BYTES" -gt "$MAX_SUBSCRIPTIONS_BYTES" ]; then
      echo ""
      echo "❌ ERROR: subscriptions value would be too large (${MERGED_SUBSCRIPTIONS_BYTES} bytes)."
      echo "   - ConfigMap object size limit is approximately ${CONFIGMAP_SIZE_LIMIT_BYTES} bytes (1 MiB)."
      echo "   - We reserve ${SUBSCRIPTIONS_SAFETY_BUFFER_BYTES} bytes for other ConfigMap keys and metadata."
      echo "   - Safety limit for subscriptions value is ${MAX_SUBSCRIPTIONS_BYTES} bytes."
      echo ""
      echo "   Refusing to patch argocd-notifications-cm.data.subscriptions to avoid exceeding the limit."
      echo "   Consider reducing per-subscription verbosity or switching to a different subscription storage strategy."
      exit 1
    fi

    # Create temporary patch file with proper JSON escaping
    TEMP_PATCH=$(mktemp)
    
    # Escape the YAML content for JSON
    # Use jq if available (most reliable), otherwise use Python (usually available)
    if command -v jq &> /dev/null; then
      # Use jq to properly escape the string (jq -Rs . returns a JSON string with quotes, we strip them)
      ESCAPED_SUBS=$(printf '%s' "$MERGED_SUBSCRIPTIONS" | jq -Rs . | sed 's/^"//;s/"$//')
    elif command -v python3 &> /dev/null; then
      # Fallback: use Python to escape (works on both macOS and Linux)
      ESCAPED_SUBS=$(printf '%s' "$MERGED_SUBSCRIPTIONS" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read())[1:-1])")
    else
      # Last resort: use awk (works on both BSD and GNU, but less reliable for complex escaping)
      ESCAPED_SUBS=$(printf '%s' "$MERGED_SUBSCRIPTIONS" | \
        awk 'BEGIN{ORS=""} {gsub(/\\/, "\\\\"); gsub(/"/, "\\\""); if (NR>1) printf "\\n"; printf "%s", $0}')
    fi
    
    cat > "$TEMP_PATCH" <<EOF
{
  "data": {
    "subscriptions": "${ESCAPED_SUBS}"
  }
}
EOF

    # Best-effort: estimate final ConfigMap size after this patch (server-side dry-run)
    # This helps catch cases where other keys (service.webhook.* entries, templates, etc.) push us over the object limit.
    echo "  🔎 Estimating final ConfigMap size after patch (server-side dry-run)..."
    if DRY_RUN_CM_JSON=$(kubectl patch configmap argocd-notifications-cm -n argocd \
      --type merge \
      --patch-file "$TEMP_PATCH" \
      --dry-run=server \
      -o json 2>/dev/null); then
      DRY_RUN_CM_BYTES=$(printf '%s' "$DRY_RUN_CM_JSON" | wc -c | tr -d ' ')
      echo "  ℹ️  Estimated ConfigMap JSON size after patch: ${DRY_RUN_CM_BYTES} bytes (limit ~${CONFIGMAP_SIZE_LIMIT_BYTES})"

      if [ "$DRY_RUN_CM_BYTES" -gt "$CONFIGMAP_SIZE_LIMIT_BYTES" ]; then
        echo ""
        echo "❌ ERROR: ConfigMap would exceed the Kubernetes/etcd object size limit after patch."
        echo "   Estimated size: ${DRY_RUN_CM_BYTES} bytes"
        echo "   Limit:          ${CONFIGMAP_SIZE_LIMIT_BYTES} bytes"
        echo ""
        echo "   Refusing to patch subscriptions to avoid a failed apply."
        exit 1
      fi
    else
      echo "  ⚠️  Could not run dry-run size estimation (insufficient permissions or older cluster)."
      echo "     Proceeding with subscriptions-only size check."
    fi

    # Patch the subscriptions field
    kubectl patch configmap argocd-notifications-cm -n argocd \
      --type merge \
      --patch-file "$TEMP_PATCH"
    
    # Clean up
    rm -f "$TEMP_PATCH"
    
    echo "  ✓ Added subscription for '${WEBHOOK_NAME}'"
  fi

  # Restart controller to reload config
  # Note: This restarts the controller for all apps, but it's necessary to pick up new webhook services
  # The restart is safe and idempotent - multiple restarts don't cause issues
  echo "🔄 Restarting notifications controller to reload configuration..."
  kubectl rollout restart deploy argocd-notifications-controller -n argocd
fi

# Verify configuration
echo ""
echo "✅ Verifying configuration..."

# Check if secrets exist
if kubectl get secret ghcr-credentials -n ${GITHUB_ORG} &> /dev/null; then
  echo "  ✓ Secret 'ghcr-credentials' exists"
else
  echo "  ✗ Secret 'ghcr-credentials' not found"
  exit 1
fi

if kubectl get secret ${APP_NAME}-argocd-${ENVIRONMENT}-repo -n argocd &> /dev/null; then
  echo "  ✓ Secret '${APP_NAME}-argocd-${ENVIRONMENT}-repo' exists"
else
  echo "  ✗ Secret '${APP_NAME}-argocd-${ENVIRONMENT}-repo' not found"
  exit 1
fi

if kubectl get secret ${APP_NAME}-config-${ENVIRONMENT}-repo -n argocd &> /dev/null; then
  echo "  ✓ Secret '${APP_NAME}-config-${ENVIRONMENT}-repo' exists"
else
  echo "  ✗ Secret '${APP_NAME}-config-${ENVIRONMENT}-repo' not found"
  exit 1
fi

# Verify notifications configuration (only for essesseff apps)
if [ "$ENABLE_NOTIFICATIONS" = true ]; then
  if kubectl get secret argocd-notifications-secret -n argocd &> /dev/null; then
    echo "  ✓ Secret 'argocd-notifications-secret' exists"
  else
    echo "  ✗ Secret 'argocd-notifications-secret' not found"
    exit 1
  fi

  # Check if configmap exists
  if kubectl get configmap argocd-notifications-cm -n argocd &> /dev/null; then
    echo "  ✓ ConfigMap 'argocd-notifications-cm' exists"
  else
    echo "  ✗ ConfigMap 'argocd-notifications-cm' not found"
    exit 1
  fi

  # Check if webhook service is configured (using repository ID)
  if kubectl get configmap argocd-notifications-cm -n argocd -o yaml | grep -q "service.webhook.webhook-${REPOSITORY_ID}"; then
    echo "  ✓ Webhook service 'webhook-${REPOSITORY_ID}' configured"
  else
    echo "  ✗ Webhook service 'webhook-${REPOSITORY_ID}' not configured"
    exit 1
  fi

  # Check if webhook subscription is configured
  if kubectl get configmap argocd-notifications-cm -n argocd -o jsonpath='{.data.subscriptions}' | grep -q "webhook-${REPOSITORY_ID}"; then
    echo "  ✓ Webhook subscription 'webhook-${REPOSITORY_ID}' configured"
  else
    echo "  ✗ Webhook subscription 'webhook-${REPOSITORY_ID}' not configured"
    exit 1
  fi

  # Check if notification controller is running
  if kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-notifications-controller | grep -q "Running"; then
    echo "  ✓ Notification controller is running"
  else
    echo "  ⚠️  Warning: Notification controller may not be running"
    echo "     Check: kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-notifications-controller"
  fi
fi

# Check if app-of-apps.yaml exists
if [ ! -f "app-of-apps.yaml" ]; then
  echo "❌ Error: app-of-apps.yaml not found"
  exit 1
fi

# Check if argocd application file exists
ARGOCD_APP_FILE="argocd/${APP_NAME}-${ENVIRONMENT}-application.yaml"
if [ ! -f "${ARGOCD_APP_FILE}" ]; then
  echo "❌ Error: ${ARGOCD_APP_FILE} not found"
  exit 1
fi

# Commit argocd app to git repo
git add ${ARGOCD_APP_FILE}
git commit -m "initial commit"
git push origin main

# Apply app-of-apps
echo "📝 Applying app-of-apps for ${ENVIRONMENT}..."
kubectl apply -f app-of-apps.yaml

echo ""
echo "=============================================="
echo "✅ Argo CD for ${APP_NAME} ${ENVIRONMENT} setup complete!"
if [ "$ENABLE_NOTIFICATIONS" = true ]; then
  echo "   (with Argo CD Notifications configured)"
else
  echo "   (Argo CD Notifications skipped - not an essesseff app)"
fi
echo "=============================================="
echo ""
if [ "$ENABLE_NOTIFICATIONS" = true ]; then
  echo "!!!REMEMBER TO DELETE YOUR SECRETS YAMLS -- DO *NOT* COMMIT THEM TO GITHUB!!!"
else
  echo "!!!REMEMBER TO DELETE YOUR SECRETS YAMLS -- DO *NOT* COMMIT THEM TO GITHUB!!!"
fi

echo ""
