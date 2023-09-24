#!/usr/bin/env bash
set -e

echo "Create base terraform templates"

if [ ! -f providers.tf ]
then
  echo "Create providers file"
  cat > providers.tf <<- PROVIDERS
provider "aws" {
  region = var.region

  default_tags {
    tags = {
      created_by = "terraform"
      workspace = terraform.workspace
    }
  }
}
PROVIDERS
fi

if [ ! -f variables.tf ]
then
  echo "Create variables file"
  cat > variables.tf <<- VARIABLES
variable "region" {
  description = "AWS region to create resources in"
  type  = string
  default = "ca-central-1"
}

variable "project_name" {
  description = "Project name"
  type  = string
  default = "project"
}

variable "api_port" {
  description = "API port"
  type  = number
  default = 3001
}
VARIABLES
fi

if [ ! -f locals.tf ]
then
  echo "Create locals template file"
  cat > locals.tf <<- LOCALS
locals {
}
LOCALS
fi

if [ ! -f ecs.tf ]
then
  echo "Create ecs template file"
  cat > ecs.tf <<- ECS
resource "aws_ecs_cluster" "api_cluster" {
  name = "\${terraform.workspace}_\${var.project_name}_api_cluster"
}
ECS
fi

if [ ! -f ecs_service.tf ]
then
  echo "Create ecs_service template file"
  cat > ecs_service.tf <<- ECS_SERVICE

resource "aws_ecs_service" "api" {
  name                               = "\${terraform.workspace}_\${var.project_name}_api"
  cluster                            = aws_ecs_cluster.api_cluster.id
  task_definition                    = aws_ecs_task_definition.task_definition.arn
  desired_count                      = var.asg_desired_capacity[terraform.workspace]
  launch_type                        = "FARGATE"
  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 50
  health_check_grace_period_seconds  = 360
  load_balancer {
    target_group_arn = aws_lb_target_group.api_tg.arn
    container_name   = "\${terraform.workspace}_\${var.project_name}_api_task"
    container_port   = var.api_port
  }
  network_configuration {
    subnets = [
      "TODO",
      "TODO"
    ]
    security_groups = [
      "TODO"
    ]
    assign_public_ip = true
  }
}
ECS_SERVICE
fi

if [ ! -f backend.tf ]
then
  echo "Create backend template file"
  cat > backend.tf <<- BACKEND
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 0.5"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "2.15.0"
    }
  }
  backend "s3" {
    hostname = "<TODO>"
  }
}
BACKEND
fi

if [ ! -f ecr.tf ]
then
  echo "Create ecr template file"
  cat > ecr.tf <<- ECR
resource "aws_ecr_repository" "ecr" {
  name = "\${terraform.workspace}-\${var.project_name}"
}
resource "docker_registry_image" "images" {
  name     = "\${aws_ecr_repository.ecr.repository_url}:latest"

  build {
    context    = "<TODO>"
    dockerfile = "Dockerfile"
    target     = "production"
   

    platform   = "linux/arm64"
  }
}

resource "aws_ecr_lifecycle_policy" "api_image_lifecycle_policy" {
  repository = aws_ecr_repository.ecr.name

  policy = <<EOF
{
    "rules": [
        {
            "rulePriority": 1,
            "description": "Keep last 10 untagged images",
            "selection": {
                "tagStatus": "untagged",
                "countType": "imageCountMoreThan",
                "countNumber": 10
            },
            "action": {
                "type": "expire"
            }
        }
    ]
}
EOF
}
ECR
fi


if [ ! -f data.tf ]
then
  echo "Create data file"
  cat > data.tf <<- DATA
data "aws_caller_identity" "current" {}

data "terraform_remote_state" "compute_gateway" {
  backend = "s3"

  config = {
    bucket = "<TODO>"
    key    = "<TODO>"
    region = "<TODO>"
  }
}
DATA
fi

if [ ! -f data.tf ]
then
  echo "Create data file"
  cat > data.tf <<- DATA
data "aws_caller_identity" "current" {}
DATA
fi

touch output.tf

if [ ! -f s3.tf ]
then
  echo "Create s3 template file"
  cat > s3.tf <<- S3
resource "aws_s3_bucket" "terraform_state" {
  bucket = "<TODO>"
  acl    = "private"
  versioning {
    enabled = true
  }
  tags = {
    Name        = "\${terraform.workspace}_\${var.project_name}_terraform_state"
    Environment = "\${terraform.workspace}"
  }
}
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_policy" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Id": "terraform_state_bucket_policy",
  "Statement": [
    {
      "Sid": "terraform_state_bucket_policy",
      "Effect": "Allow",
      "Principal": {
        "AWS": [
          "arn:aws:iam::\${data.aws_caller_identity.current.account_id}:root"
        ]
      },
      "Action": [
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": [
        "arn:aws:s3:::\${aws_s3_bucket.terraform_state.id}/*"
      ]
    }
  ]
}
EOF
}
S3
fi



echo "Create .gitignore file"
cat > .gitignore <<- IGNORE
**/.terraform/**
**/.terragrunt-cache/**
IGNORE
