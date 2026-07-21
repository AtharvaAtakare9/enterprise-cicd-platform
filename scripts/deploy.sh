#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="us-east-1"
ECR_REPO="expense-tracker-backend"
CLUSTER="expense-tracker-eks"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
TAG=$(git rev-parse --short HEAD)

echo "==> Login to ECR"
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$REGISTRY"

echo "==> Build & push image"
docker build -f docker/Dockerfile -t "$REGISTRY/$ECR_REPO:$TAG" .
docker push "$REGISTRY/$ECR_REPO:$TAG"

echo "==> Update kubeconfig"
aws eks update-kubeconfig --name "$CLUSTER" --region "$AWS_REGION"

echo "-- cleaning up any previous migration job (robust, avoids stuck Terminating state)"
kubectl -n expense-tracker-prod delete pod -l job-name=expense-tracker-db-migrate --force --grace-period=0 --ignore-not-found=true 2>/dev/null || true
kubectl -n expense-tracker-prod patch job expense-tracker-db-migrate -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
kubectl -n expense-tracker-prod delete job expense-tracker-db-migrate --force --grace-period=0 --ignore-not-found=true 2>/dev/null || true
for i in $(seq 1 15); do
  kubectl -n expense-tracker-prod get job expense-tracker-db-migrate >/dev/null 2>&1 || break
  sleep 2
done

echo "==> Set image via kustomize + apply"
cd k8s/overlays/prod
kustomize edit set image "REPLACE_ME/expense-tracker-backend=$REGISTRY/$ECR_REPO:$TAG"
kubectl apply -k .

echo "==> Done. Tag deployed: $TAG"
