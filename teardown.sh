#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $*"; }

info "Removing ArgoCD Application..."
kubectl delete -f argocd/application.yaml --ignore-not-found

info "Removing ArgoCD installation..."
kubectl delete -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml \
  --ignore-not-found

info "Deleting argocd namespace..."
kubectl delete namespace argocd --ignore-not-found

info "Teardown complete."
