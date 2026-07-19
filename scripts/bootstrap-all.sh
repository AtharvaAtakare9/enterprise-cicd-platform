#!/usr/bin/env bash
# bootstrap-all.sh
# Works from Git Bash (Windows) OR a real Linux/WSL/macOS shell.
# Fully automated: checks/installs tools where possible, creates key pair,
# builds AWS infra (VPC/EKS/ECR/ALB/EC2/RDS), configures servers with Ansible
# (skipped automatically if not on Linux), installs ArgoCD, creates secrets,
# wires the ECR registry, and deploys the app. Database migrations run
# automatically inside the cluster as a Kubernetes Job on every deploy.
#
# Usage:
#   chmod +x scripts/bootstrap-all.sh
#   ./scripts/bootstrap-all.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [ ! -f scripts/config.env ]; then
  echo "Missing scripts/config.env."
  exit 1
fi
source scripts/config.env

HAS_APT=false
if command -v apt-get >/dev/null 2>&1; then
  HAS_APT=true
fi

check_or_install() {
  local cmd="$1" installer="$2" winget_hint="$3"
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "-- $cmd already installed"
    return 0
  fi
  if [ "$HAS_APT" = true ]; then
    echo "-- $cmd not found, installing via apt..."
    eval "$installer"
    return 0
  fi
  echo ""
  echo "!! $cmd is not installed and this shell (Git Bash) can't auto-install Linux packages."
  echo "   Open a normal Windows PowerShell (not Git Bash) and run:"
  echo "     $winget_hint"
  echo "   Then close and reopen Git Bash and re-run this script."
  echo ""
  return 1
}

echo "=== [1/10] Checking required tools ==="
MISSING=0
check_or_install terraform '
  curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
  sudo apt update && sudo apt install -y terraform
' 'winget install -e --id Hashicorp.Terraform' || MISSING=1

check_or_install kubectl '
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
' 'winget install -e --id Kubernetes.kubectl' || MISSING=1

check_or_install kustomize '
  curl -L -o /tmp/kustomize.tar.gz "https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv5.4.3/kustomize_v5.4.3_linux_amd64.tar.gz"
  tar -xzf /tmp/kustomize.tar.gz -C /tmp
  sudo mv /tmp/kustomize /usr/local/bin/
  rm -f /tmp/kustomize.tar.gz
' 'choco install kustomize   (or download from https://github.com/kubernetes-sigs/kustomize/releases)' || MISSING=1

check_or_install aws '
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip -o awscliv2.zip
  sudo ./aws/install --update
  rm -rf awscliv2.zip aws
' 'winget install -e --id Amazon.AWSCLI' || MISSING=1

check_or_install docker 'echo "install Docker Desktop manually"' 'winget install -e --id Docker.DockerDesktop  (then open it once, and enable it)' || MISSING=1

if [ "$MISSING" -eq 1 ]; then
  echo "One or more required tools are missing. Install them as shown above, then re-run this script."
  exit 1
fi

HAS_ANSIBLE=false
if command -v ansible-playbook >/dev/null 2>&1; then
  HAS_ANSIBLE=true
elif [ "$HAS_APT" = true ]; then
  echo "-- installing ansible..."
  sudo apt update && sudo apt install -y ansible
  HAS_ANSIBLE=true
else
  echo "-- ansible not available in this shell (Git Bash) — will skip the optional server-configuration step."
  echo "   (Not required: your app runs on managed EKS nodes, not plain EC2 servers.)"
fi

aws sts get-caller-identity >/dev/null 2>&1 || {
  echo "AWS CLI is not configured. Run 'aws configure' once, then re-run this script."
  exit 1
}

echo "=== [2/10] Creating EC2 key pair '$KEY_PAIR_NAME' (skips if it exists) ==="
if ! aws ec2 describe-key-pairs --key-names "$KEY_PAIR_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  aws ec2 create-key-pair --key-name "$KEY_PAIR_NAME" --region "$AWS_REGION" \
    --query 'KeyMaterial' --output text > "$ROOT_DIR/${KEY_PAIR_NAME}.pem"
  chmod 400 "$ROOT_DIR/${KEY_PAIR_NAME}.pem" 2>/dev/null || true
  echo "-- created and saved ${KEY_PAIR_NAME}.pem in project root (keep this safe)"
else
  echo "-- key pair $KEY_PAIR_NAME already exists in AWS"
fi

echo "=== [3/10] Creating Terraform state bucket (skips if it exists) ==="
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
TF_STATE_BUCKET="${TF_STATE_BUCKET}-${ACCOUNT_ID}"
echo "-- using bucket name: $TF_STATE_BUCKET (account ID appended for global uniqueness)"
if ! aws s3api head-bucket --bucket "$TF_STATE_BUCKET" 2>/dev/null; then
  aws s3 mb "s3://$TF_STATE_BUCKET" --region "$AWS_REGION"
  aws s3api put-bucket-versioning --bucket "$TF_STATE_BUCKET" --versioning-configuration Status=Enabled
else
  echo "-- bucket $TF_STATE_BUCKET already exists"
fi

echo "=== [4/10] Terraform init/plan/apply (VPC, EKS, ECR, ALB, EC2, RDS) ==="
cd "$ROOT_DIR/terraform/envs/prod"
terraform init -input=false -backend-config="bucket=${TF_STATE_BUCKET}"
terraform plan -out=tfplan -input=false -var="key_pair_name=${KEY_PAIR_NAME}"
terraform apply -input=false -auto-approve tfplan

ECR_URL=$(terraform output -raw ecr_repository_url)
ECR_REGISTRY="${ECR_URL%%/*}"
ALB_DNS=$(terraform output -raw alb_dns_name)
EC2_IP=$(terraform output -raw ec2_public_ip)
DB_ENDPOINT=$(terraform output -raw db_endpoint)
DB_PORT=$(terraform output -raw db_port)
DB_NAME=$(terraform output -raw db_name)
DB_USER=$(terraform output -raw db_username)
DB_PASS=$(terraform output -raw db_password)
DATABASE_URL="postgresql://${DB_USER}:${DB_PASS}@${DB_ENDPOINT}:${DB_PORT}/${DB_NAME}?uselibpqcompat=true&sslmode=require"
cd "$ROOT_DIR"

if [ -z "${JWT_SECRET:-}" ]; then
  echo "-- JWT_SECRET blank, generating one automatically"
  if command -v openssl >/dev/null 2>&1; then
    JWT_SECRET=$(openssl rand -hex 32)
  else
    JWT_SECRET=$(date +%s%N | sha256sum | head -c 64)
  fi
fi

echo "=== [5/10] Configuring servers with Ansible (skipped if unavailable) ==="
if [ "$HAS_ANSIBLE" = true ]; then
  cd "$ROOT_DIR/ansible"
  ansible-playbook -i inventory/aws_ec2.yml playbooks/site.yml || \
    echo "-- no matching hosts yet, continuing (this is OK)"
  cd "$ROOT_DIR"
else
  echo "-- skipped (ansible not available in this shell)"
fi

echo "=== [6/10] Connecting kubectl to the cluster ==="
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$AWS_REGION"
kubectl get nodes

echo "=== [7/10] Installing ArgoCD ==="
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
kubectl apply --server-side --force-conflicts -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
kubectl apply -f argocd/application.yaml
ARGOCD_PASS=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

echo "=== [8/10] Creating app secrets (includes DB connection for auto-migration) ==="
kubectl create namespace expense-tracker-prod --dry-run=client -o yaml | kubectl apply -f -
kubectl -n expense-tracker-prod create secret generic expense-tracker-secrets \
  --from-literal=DATABASE_URL="$DATABASE_URL" \
  --from-literal=JWT_SECRET="$JWT_SECRET" \
  --from-literal=JWT_EXPIRY="$JWT_EXPIRY" \
  --from-literal=NODE_ENV="production" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "=== [9/10] Wiring ECR registry into kustomize overlays ==="
sed -i "s|<ECR_REGISTRY>|${ECR_REGISTRY}|g" k8s/overlays/dev/kustomization.yaml
sed -i "s|<ECR_REGISTRY>|${ECR_REGISTRY}|g" k8s/overlays/prod/kustomization.yaml

echo "=== [10/10] Build + push + deploy (DB tables created automatically by the migration Job) ==="
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REGISTRY"
TAG=$(git rev-parse --short HEAD 2>/dev/null || date +%s)
docker build -f docker/Dockerfile -t "$ECR_REGISTRY/$ECR_REPO_NAME:$TAG" .
docker push "$ECR_REGISTRY/$ECR_REPO_NAME:$TAG"

cd k8s/overlays/prod
kustomize edit set image "REPLACE_ME/expense-tracker-backend=${ECR_REGISTRY}/${ECR_REPO_NAME}:${TAG}"
cd "$ROOT_DIR"

kubectl -n expense-tracker-prod delete job expense-tracker-db-migrate --ignore-not-found=true
kubectl apply -k k8s/overlays/prod

echo "-- waiting for migration job to finish..."
kubectl -n expense-tracker-prod wait --for=condition=complete job/expense-tracker-db-migrate --timeout=120s || \
  echo "-- migration job did not report complete in time, check with: kubectl -n expense-tracker-prod logs job/expense-tracker-db-migrate"

echo ""
echo "================ DONE ================"
echo "ArgoCD admin password  : $ARGOCD_PASS"
echo "Load balancer address  : http://$ALB_DNS/"
echo "EC2 server public IP   : $EC2_IP  (ssh -i ${KEY_PAIR_NAME}.pem ubuntu@$EC2_IP)"
echo "Database endpoint      : $DB_ENDPOINT (tables created automatically by the migration Job)"
echo "JWT secret used        : $JWT_SECRET"
echo "Check pods with        : kubectl -n expense-tracker-prod get pods,svc,ingress,hpa"
echo "Check migration logs   : kubectl -n expense-tracker-prod logs job/expense-tracker-db-migrate"
echo "SAVE THIS OUTPUT — passwords are not shown again automatically."
echo "========================================"
