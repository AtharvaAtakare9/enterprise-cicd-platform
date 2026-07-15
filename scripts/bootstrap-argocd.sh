#!/usr/bin/env bash
set -euo pipefail

kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply --server-side --force-conflicts -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

echo "Waiting for ArgoCD server..."
kubectl -n argocd rollout status deploy/argocd-server --timeout=180s

kubectl apply -f argocd/application.yaml

echo "ArgoCD admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo
