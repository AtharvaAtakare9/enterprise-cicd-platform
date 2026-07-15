variable "name" {
  type    = string
  default = "expense-tracker-db"
}

variable "db_name" {
  type    = string
  default = "expense_tracker"
}

variable "username" {
  type    = string
  default = "postgres"
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "allowed_cidr" {
  description = "CIDR allowed to reach the DB (VPC range)"
  type        = string
  default     = "10.0.0.0/16"
}

resource "random_password" "db" {
  length  = 20
  special = false
}

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-subnet-group"
  subnet_ids = var.private_subnet_ids
}

resource "aws_security_group" "db" {
  name   = "${var.name}-sg"
  vpc_id = var.vpc_id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "this" {
  identifier             = var.name
  engine                 = "postgres"
  engine_version         = "16.4"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_name                = var.db_name
  username               = var.username
  password               = random_password.db.result
  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false
  skip_final_snapshot    = true
  backup_retention_period = 1
}

output "endpoint" {
  value = aws_db_instance.this.address
}

output "port" {
  value = aws_db_instance.this.port
}

output "db_name" {
  value = aws_db_instance.this.db_name
}

output "username" {
  value = aws_db_instance.this.username
}

output "password" {
  value     = random_password.db.result
  sensitive = true
}
