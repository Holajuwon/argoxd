#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'; NC='\033[0m'
info() { echo -e "${GREEN}[INFO]${NC} $*"; }

info "Removing ArgoCD Applications..."
kubectl delete -f argocd/application.yaml --ignore-not-found
kubectl delete -f argocd/work-application.yaml --ignore-not-found

info "Removing managed resources in default namespace..."
kubectl delete configmap argoxd-work-files argoxd-scripts argoxd-config --ignore-not-found -n default
kubectl delete deployment argoxd --ignore-not-found -n default
kubectl delete service argoxd --ignore-not-found -n default
kubectl delete job argoxd-sync-job --ignore-not-found -n default

info "Removing ArgoCD installation..."
kubectl delete -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml \
  --ignore-not-found

info "Deleting argocd namespace..."
kubectl delete namespace argocd --ignore-not-found

info "Teardown complete."
