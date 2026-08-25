#!/usr/bin/env bash
set -euo pipefail

# ─── colours ──────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warning() { echo -e "${YELLOW}[WARN]${NC} $*"; }

# ─── 1. Verify prerequisites ──────────────────────────────────────────────────
info "Checking prerequisites..."
for cmd in kubectl helm git; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: '$cmd' is not installed or not on PATH." >&2; exit 1
  fi
done

# Confirm kubectl is pointing at Rancher Desktop / k3s
CONTEXT=$(kubectl config current-context)
info "Active kubectl context: ${CONTEXT}"
if [[ "$CONTEXT" != *rancher* ]] && [[ "$CONTEXT" != *k3s* ]]; then
  warning "Context doesn't look like Rancher Desktop. Continuing anyway — press Ctrl-C to abort."
  sleep 3
fi

# ─── 2. Install ArgoCD ────────────────────────────────────────────────────────
info "Creating argocd namespace (idempotent)..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

info "Applying ArgoCD stable install manifest..."
kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

info "Waiting for ArgoCD pods to be ready (up to 3 min)..."
kubectl wait --for=condition=Ready pods --all -n argocd --timeout=180s

# ─── 3. Retrieve initial admin password ───────────────────────────────────────
ARGOCD_PASSWORD=$(kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath="{.data.password}" | base64 -d)

echo ""
echo "──────────────────────────────────────────────────────"
echo "  ArgoCD admin password: ${ARGOCD_PASSWORD}"
echo "──────────────────────────────────────────────────────"
echo ""

# ─── 4. Apply the ArgoCD Application manifest ────────────────────────────────
info "Applying ArgoCD Application manifest..."
kubectl apply -f argocd/application.yaml

# ─── 5. Port-forward instructions ────────────────────────────────────────────
echo ""
info "Setup complete!"
echo ""
echo "  Open the ArgoCD UI:  https://localhost:8080"
echo "  Username:            admin"
echo "  Password:            ${ARGOCD_PASSWORD}"
echo ""
echo "  Run this to open the port-forward:"
echo "    kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo ""
echo "  Or log in via CLI:"
echo "    argocd login localhost:8080 --username admin --password '${ARGOCD_PASSWORD}' --insecure"
echo ""
