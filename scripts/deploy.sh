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

echo "==> Delete old migration job (jobs are immutable, must recreate)"
kubectl -n expense-tracker-prod delete job expense-tracker-db-migrate --ignore-not-found=true

echo "==> Set image via kustomize + apply"
cd k8s/overlays/prod
kustomize edit set image "REPLACE_ME/expense-tracker-backend=$REGISTRY/$ECR_REPO:$TAG"
kubectl apply -k .

echo "==> Done. Tag deployed: $TAG"
