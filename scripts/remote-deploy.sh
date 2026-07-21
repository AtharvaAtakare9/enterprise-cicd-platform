#!/usr/bin/env bash
# remote-deploy.sh
# Run this ON THE EC2 SERVER (after SSHing in), not on your laptop.
# The server already has Docker/kubectl/kustomize/Ansible/ArgoCD CLI installed
# automatically via Terraform user_data, and has AWS permissions via its
# instance role, so no 'aws configure' is needed here either.

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source scripts/config.env
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
TF_STATE_BUCKET="${TF_STATE_BUCKET}-${ACCOUNT_ID}"

echo "=== Reading infra details from Terraform state (shared via S3 backend) ==="
cd terraform/envs/prod
terraform init -input=false -backend-config="bucket=${TF_STATE_BUCKET}"
ECR_URL=$(terraform output -raw ecr_repository_url)
ECR_REGISTRY="${ECR_URL%%/*}"
DB_ENDPOINT=$(terraform output -raw db_endpoint)
DB_PORT=$(terraform output -raw db_port)
DB_NAME=$(terraform output -raw db_name)
DB_USER=$(terraform output -raw db_username)
DB_PASS=$(terraform output -raw db_password)
DATABASE_URL="postgresql://${DB_USER}:${DB_PASS}@${DB_ENDPOINT}:${DB_PORT}/${DB_NAME}?uselibpqcompat=true&sslmode=require"
cd "$ROOT_DIR"

if [ -z "${JWT_SECRET:-}" ]; then
  JWT_SECRET=$(openssl rand -hex 32)
fi

echo "=== Configuring servers with Ansible ==="
cd ansible
ansible-playbook -i inventory/aws_ec2.yml playbooks/site.yml || echo "-- no matching hosts, continuing"
cd "$ROOT_DIR"

echo "=== Connecting kubectl to the cluster ==="
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"

echo "-- ensuring cluster access mode allows access entries..."
aws eks update-cluster-config --name "$CLUSTER_NAME" --region "$AWS_REGION" \
  --access-config authenticationMode=API_AND_CONFIG_MAP >/dev/null 2>&1 || true
for i in $(seq 1 20); do
  STATUS=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" --query "cluster.status" --output text 2>/dev/null || echo "")
  [ "$STATUS" = "ACTIVE" ] && break
  sleep 10
done

echo "-- opening NodePort range on the cluster security group..."
CLUSTER_SG=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$AWS_REGION" \
  --query "cluster.resourcesVpcConfig.clusterSecurityGroupId" --output text)
aws ec2 authorize-security-group-ingress --region "$AWS_REGION" \
  --group-id "$CLUSTER_SG" --protocol tcp --port 30000-32767 --cidr 0.0.0.0/0 >/dev/null 2>&1 || \
  echo "-- (rule likely already exists, continuing)"

kubectl get nodes

echo "=== Installing ArgoCD ==="
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply --server-side --force-conflicts -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
kubectl apply -f argocd/application.yaml
ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo "=== Creating app secrets ==="
kubectl create namespace expense-tracker-prod --dry-run=client -o yaml | kubectl apply -f -
kubectl -n expense-tracker-prod create secret generic expense-tracker-secrets \
  --from-literal=DATABASE_URL="$DATABASE_URL" \
  --from-literal=JWT_SECRET="$JWT_SECRET" \
  --from-literal=JWT_EXPIRY="$JWT_EXPIRY" \
  --from-literal=NODE_ENV="production" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "=== Build + push + deploy (DB migration runs automatically as a Job) ==="
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REGISTRY"
TAG=$(date +%s)
sudo docker build -f docker/Dockerfile -t "$ECR_REGISTRY/$ECR_REPO_NAME:$TAG" .
sudo docker push "$ECR_REGISTRY/$ECR_REPO_NAME:$TAG"

cd k8s/overlays/prod
kustomize edit set image "REPLACE_ME/expense-tracker-backend=${ECR_REGISTRY}/${ECR_REPO_NAME}:${TAG}"
cd "$ROOT_DIR"

echo "-- cleaning up any previous migration job (robust, avoids stuck Terminating state)"
kubectl -n expense-tracker-prod delete pod -l job-name=expense-tracker-db-migrate --force --grace-period=0 --ignore-not-found=true 2>/dev/null || true
kubectl -n expense-tracker-prod patch job expense-tracker-db-migrate -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
kubectl -n expense-tracker-prod delete job expense-tracker-db-migrate --force --grace-period=0 --ignore-not-found=true 2>/dev/null || true
for i in $(seq 1 15); do
  kubectl -n expense-tracker-prod get job expense-tracker-db-migrate >/dev/null 2>&1 || break
  sleep 2
done
kubectl apply -k k8s/overlays/prod

echo "-- waiting for migration job..."
kubectl -n expense-tracker-prod wait --for=condition=complete job/expense-tracker-db-migrate --timeout=120s || \
  echo "-- check logs: kubectl -n expense-tracker-prod logs job/expense-tracker-db-migrate"

echo ""
echo "-- waiting for the LoadBalancer service to get a real address..."
SVC_LB=""
for i in $(seq 1 30); do
  SVC_LB=$(kubectl -n expense-tracker-prod get svc expense-tracker-backend -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  if [ -n "$SVC_LB" ]; then break; fi
  sleep 10
done

echo ""
echo "================ DONE ================"
echo "ArgoCD admin password : $ARGOCD_PASS"
echo "App URL (use this one) : http://${SVC_LB:-<not-ready-yet-check-kubectl-get-svc>}/"
echo "Database endpoint     : $DB_ENDPOINT"
echo "JWT secret used       : $JWT_SECRET"
echo "Check pods with       : kubectl -n expense-tracker-prod get pods,svc,ingress,hpa"
echo "SAVE THIS OUTPUT — passwords not shown again."
echo "========================================"
