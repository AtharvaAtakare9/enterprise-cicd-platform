#!/usr/bin/env bash
# bootstrap-infra-only.sh
# Run this on your LAPTOP. Only needs: terraform, aws cli (both already installed).
# Creates the key pair, state bucket, and all AWS infrastructure — including the
# EC2 server, which auto-installs Docker/kubectl/kustomize/Ansible/ArgoCD CLI on
# itself via user_data. Everything after this runs ON the server instead of your
# laptop — see scripts/remote-deploy.sh.

set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source scripts/config.env

aws sts get-caller-identity >/dev/null 2>&1 || {
  echo "AWS CLI not configured. Run 'aws configure' first."
  exit 1
}

echo "=== Creating EC2 key pair '$KEY_PAIR_NAME' (skips if it exists) ==="
if ! aws ec2 describe-key-pairs --key-names "$KEY_PAIR_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  aws ec2 create-key-pair --key-name "$KEY_PAIR_NAME" --region "$AWS_REGION" \
    --query 'KeyMaterial' --output text > "$ROOT_DIR/${KEY_PAIR_NAME}.pem"
  chmod 400 "$ROOT_DIR/${KEY_PAIR_NAME}.pem" 2>/dev/null || true
  echo "-- saved ${KEY_PAIR_NAME}.pem in project root. KEEP THIS FILE — it's your SSH key."
else
  echo "-- key pair already exists"
fi

echo "=== Creating Terraform state bucket (skips if it exists) ==="
if ! aws s3api head-bucket --bucket "$TF_STATE_BUCKET" 2>/dev/null; then
  aws s3 mb "s3://$TF_STATE_BUCKET" --region "$AWS_REGION"
  aws s3api put-bucket-versioning --bucket "$TF_STATE_BUCKET" --versioning-configuration Status=Enabled
else
  echo "-- bucket already exists"
fi

echo "=== Terraform init/plan/apply (VPC, EKS, ECR, ALB, EC2, RDS) ==="
cd terraform/envs/prod
terraform init -input=false
terraform plan -out=tfplan -input=false -var="key_pair_name=${KEY_PAIR_NAME}"
terraform apply -input=false -auto-approve tfplan

EC2_IP=$(terraform output -raw ec2_public_ip)
cd "$ROOT_DIR"

echo ""
echo "================ INFRA READY ================"
echo "EC2 server public IP : $EC2_IP"
echo ""
echo "Next steps:"
echo "1. Wait 2-3 minutes for the server to finish installing its own tools."
echo "2. Copy your project onto the server:"
echo "     scp -i ${KEY_PAIR_NAME}.pem -r \"$ROOT_DIR\" ubuntu@${EC2_IP}:~/cicd-platform"
echo "3. SSH into the server:"
echo "     ssh -i ${KEY_PAIR_NAME}.pem ubuntu@${EC2_IP}"
echo "4. On the server, check tools finished installing:"
echo "     ls ~/tools-ready   (wait until this file exists)"
echo "5. Then run the remote deploy script (on the server):"
echo "     cd ~/cicd-platform && chmod +x scripts/remote-deploy.sh && ./scripts/remote-deploy.sh"
echo "==============================================="
