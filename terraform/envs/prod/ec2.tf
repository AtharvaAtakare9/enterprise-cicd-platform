variable "key_pair_name" {
  description = "Name of an existing EC2 key pair for SSH access"
  type        = string
  default     = "New-key"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_security_group" "ec2_server" {
  name   = "expense-tracker-ec2-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # tighten to your IP for real use
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_iam_role" "ec2_server" {
  name = "expense-tracker-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# NOTE: AdministratorAccess is used here for simplicity so the server can run
# terraform/eks/ecr/rds commands without you copying AWS keys onto it. For a
# real production setup, replace this with a narrower policy.
resource "aws_iam_role_policy_attachment" "ec2_admin" {
  role       = aws_iam_role.ec2_server.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_iam_instance_profile" "ec2_server" {
  name = "expense-tracker-ec2-profile"
  role = aws_iam_role.ec2_server.name
}

locals {
  ec2_user_data = <<-EOF
    #!/bin/bash
    set -e
    apt-get update
    apt-get install -y unzip curl git jq

    # Docker
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker ubuntu

    # AWS CLI
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip
    ./aws/install
    rm -rf awscliv2.zip aws

    # kubectl
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
    rm -f kubectl

    # kustomize
    curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash
    mv kustomize /usr/local/bin/

    # terraform (so the server can also apply infra changes if needed)
    curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/hashicorp.list
    apt-get update && apt-get install -y terraform ansible

    # ArgoCD CLI
    curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
    chmod +x /usr/local/bin/argocd

    touch /home/ubuntu/tools-ready
  EOF
}

resource "aws_instance" "app_server" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.medium"
  subnet_id              = module.vpc.public_subnet_ids[0]
  key_name               = var.key_pair_name
  vpc_security_group_ids = [aws_security_group.ec2_server.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2_server.name
  user_data              = local.ec2_user_data

  tags = {
    Name    = "expense-tracker-app-server"
    Project = "expense-tracker"
    Role    = "app"
  }
}

output "ec2_public_ip" {
  value = aws_instance.app_server.public_ip
}
