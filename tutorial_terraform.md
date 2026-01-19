# Terraform Review Tutorial for DevOps Engineers

## Introduction

Welcome back to Terraform! This tutorial assumes you understand Infrastructure as Code (IaC) concepts but need a practical refresh on Terraform specifics. We'll cover modern best practices and features you might have missed.

## Current State of Terraform (2025)

**Latest Stable Version**: Terraform 1.10.x
**Major Changes Since 2022-2023**:

- Enhanced state management capabilities
- Improved testing framework
- Better error messages and planning output
- Native support for more cloud providers

## Part 1: Core Concepts Refresher

### The Terraform Workflow

The fundamental workflow remains unchanged:

```bash
terraform init     # Initialize working directory
terraform plan     # Preview changes
terraform apply    # Execute changes
terraform destroy  # Tear down infrastructure
```

### HCL Syntax Essentials

Terraform uses HashiCorp Configuration Language (HCL). Here's a quick syntax reminder:

```hcl
# Resource declaration
resource "provider_resource_type" "local_name" {
  argument1 = "value"
  argument2 = 123

  nested_block {
    setting = "value"
  }
}

# Variable declaration
variable "instance_type" {
  type        = string
  description = "EC2 instance type"
  default     = "t3.micro"
}

# Output declaration
output "instance_ip" {
  value       = aws_instance.web.public_ip
  description = "Public IP of web server"
}

# Data source
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}
```

## Part 2: Modern Project Structure

A well-organized Terraform project in 2025 typically looks like this:

```shell
terraform-project/
├── environments/
│   ├── dev/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── terraform.tfvars
│   ├── staging/
│   │   └── ...
│   └── prod/
│       └── ...
├── modules/
│   ├── networking/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   ├── compute/
│   │   └── ...
│   └── database/
│       └── ...
├── .terraform.lock.hcl
├── .gitignore
└── README.md
```

### Key Files Explained

**main.tf**: Primary configuration
**variables.tf**: Input variable declarations
**outputs.tf**: Output value declarations
**terraform.tfvars**: Variable value assignments (don't commit secrets!)
**.terraform.lock.hcl**: Dependency lock file (commit this)

## Part 3: Hands-On Example - AWS Infrastructure

Let's build a practical example: a VPC with an EC2 instance.

### Step 1: Provider Configuration

```hcl
# main.tf
terraform {
  required_version = ">= 1.8"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state backend (best practice)
  backend "s3" {
    bucket         = "my-terraform-state-bucket"
    key            = "dev/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = var.environment
      ManagedBy   = "Terraform"
      Project     = "DevOps-Demo"
    }
  }
}
```

### Step 2: Variables

```hcl
# variables.tf
variable "aws_region" {
  type        = string
  description = "AWS region for resources"
  default     = "us-west-2"
}

variable "environment" {
  type        = string
  description = "Environment name"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "vpc_cidr" {
  type        = string
  description = "CIDR block for VPC"
  default     = "10.0.0.0/16"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type"
  default     = "t3.micro"
}

variable "allowed_ssh_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to SSH"
  default     = []
}
```

### Step 3: VPC and Networking

```hcl
# networking.tf
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.environment}-vpc"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 1)
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.environment}-public-subnet-1"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.environment}-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.environment}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

data "aws_availability_zones" "available" {
  state = "available"
}
```

### Step 4: Security Groups

```hcl
# security.tf
resource "aws_security_group" "web" {
  name        = "${var.environment}-web-sg"
  description = "Security group for web servers"
  vpc_id      = aws_vpc.main.id

  # HTTP
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTP"
  }

  # HTTPS
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS"
  }

  # SSH (restricted)
  dynamic "ingress" {
    for_each = length(var.allowed_ssh_cidrs) > 0 ? [1] : []
    content {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.allowed_ssh_cidrs
      description = "Allow SSH from specific IPs"
    }
  }

  # Outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound"
  }

  tags = {
    Name = "${var.environment}-web-sg"
  }
}
```

### Step 5: Compute Resources

```hcl
# compute.tf
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "web" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public.id

  vpc_security_group_ids = [aws_security_group.web.id]

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "<h1>Hello from Terraform on ${var.environment}</h1>" > /var/www/html/index.html
              EOF

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"  # IMDSv2
  }

  tags = {
    Name = "${var.environment}-web-server"
  }
}
```

### Step 6: Outputs

```hcl
# outputs.tf
output "vpc_id" {
  value       = aws_vpc.main.id
  description = "VPC ID"
}

output "instance_id" {
  value       = aws_instance.web.id
  description = "EC2 instance ID"
}

output "instance_public_ip" {
  value       = aws_instance.web.public_ip
  description = "Public IP of web server"
}

output "web_url" {
  value       = "http://${aws_instance.web.public_ip}"
  description = "URL to access web server"
}
```

### Step 7: Variable Values

```hcl
# terraform.tfvars
environment      = "dev"
aws_region       = "us-west-2"
vpc_cidr         = "10.0.0.0/16"
instance_type    = "t3.micro"
allowed_ssh_cidrs = ["203.0.113.0/24"]  # Replace with your IP
```

## Part 4: Advanced Features You Should Know

### Terraform Functions

Terraform has built-in functions that are essential for DRY code:

```hcl
# String manipulation
locals {
  name_prefix = "${var.project}-${var.environment}"
  upper_env   = upper(var.environment)

  # Collections
  availability_zones = slice(data.aws_availability_zones.available.names, 0, 3)

  # Type conversion
  port_number = tonumber(var.app_port)

  # Conditionals
  instance_count = var.environment == "prod" ? 3 : 1
}

# CIDR manipulation
resource "aws_subnet" "private" {
  count             = 3
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = element(local.availability_zones, count.index)
}

# File functions
user_data = templatefile("${path.module}/user-data.sh", {
  environment = var.environment
  app_port    = var.app_port
})
```

### For Expressions and Dynamic Blocks

```hcl
# For expressions
locals {
  subnet_ids = [for s in aws_subnet.private : s.id]

  subnet_cidrs = {
    for idx, subnet in aws_subnet.private :
    subnet.availability_zone => subnet.cidr_block
  }
}

# Dynamic blocks
resource "aws_security_group" "app" {
  name   = "app-sg"
  vpc_id = aws_vpc.main.id

  dynamic "ingress" {
    for_each = var.allowed_ports
    content {
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = "tcp"
      cidr_blocks = ingress.value.cidrs
      description = ingress.value.description
    }
  }
}

# Variable definition for above
variable "allowed_ports" {
  type = list(object({
    port        = number
    cidrs       = list(string)
    description = string
  }))
  default = [
    {
      port        = 80
      cidrs       = ["0.0.0.0/0"]
      description = "HTTP"
    },
    {
      port        = 443
      cidrs       = ["0.0.0.0/0"]
      description = "HTTPS"
    }
  ]
}
```

### Count vs For_Each

```hcl
# Count - use when creating identical resources
resource "aws_instance" "web" {
  count         = var.instance_count
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  tags = {
    Name = "web-${count.index + 1}"
  }
}

# For_each - use when creating resources based on a map/set
resource "aws_iam_user" "developers" {
  for_each = toset(var.developer_names)
  name     = each.value
}

variable "developer_names" {
  type    = list(string)
  default = ["alice", "bob", "charlie"]
}

# Accessing for_each resources
output "developer_arns" {
  value = [for user in aws_iam_user.developers : user.arn]
}
```

## Part 5: State Management Best Practices

### Remote State Backend

Always use remote state in team environments:

```hcl
# S3 backend with locking
terraform {
  backend "s3" {
    bucket         = "company-terraform-state"
    key            = "project/environment/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "terraform-locks"

    # Workspace support
    workspace_key_prefix = "workspaces"
  }
}
```

### State Commands

```bash
# View state
terraform state list
terraform state show aws_instance.web

# Move resources (refactoring)
terraform state mv aws_instance.web aws_instance.app

# Remove from state (not infrastructure)
terraform state rm aws_instance.old

# Import existing resources
terraform import aws_instance.existing i-1234567890abcdef0

# Refresh state
terraform refresh

# Pull remote state
terraform state pull > terraform.tfstate.backup
```

### Workspaces

```bash
# Create and use workspaces
terraform workspace new dev
terraform workspace new staging
terraform workspace new prod

# List workspaces
terraform workspace list

# Switch workspace
terraform workspace select dev

# Use workspace in config
resource "aws_instance" "web" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = terraform.workspace == "prod" ? "t3.medium" : "t3.micro"

  tags = {
    Name        = "web-${terraform.workspace}"
    Environment = terraform.workspace
  }
}
```

## Part 6: Modules

### Creating a Module

```hcl
# modules/vpc/main.tf
variable "vpc_cidr" {
  type = string
}

variable "environment" {
  type = string
}

variable "availability_zones" {
  type = list(string)
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true

  tags = {
    Name        = "${var.environment}-vpc"
    Environment = var.environment
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.environment}-public-${count.index + 1}"
  }
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}
```

### Using a Module

```hcl
# Root configuration
module "vpc" {
  source = "./modules/vpc"

  vpc_cidr           = "10.0.0.0/16"
  environment        = var.environment
  availability_zones = ["us-west-2a", "us-west-2b"]
}

# Reference module outputs
resource "aws_instance" "web" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  subnet_id     = module.vpc.public_subnet_ids[0]
}

# Using public registry modules
module "vpc_from_registry" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"

  name = "${var.environment}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["us-west-2a", "us-west-2b", "us-west-2c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  enable_vpn_gateway = false

  tags = {
    Environment = var.environment
  }
}
```

## Part 7: DevOps Integration

### CI/CD Pipeline Integration

```yaml
# Example GitHub Actions workflow
name: Terraform

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

env:
  TF_VERSION: 1.10.0
  AWS_REGION: us-west-2

jobs:
  terraform:
    name: Terraform Plan/Apply
    runs-on: ubuntu-latest

    steps:
    - name: Checkout
      uses: actions/checkout@v4

    - name: Setup Terraform
      uses: hashicorp/setup-terraform@v3
      with:
        terraform_version: ${{ env.TF_VERSION }}

    - name: Configure AWS Credentials
      uses: aws-actions/configure-aws-credentials@v4
      with:
        role-to-assume: ${{ secrets.AWS_ROLE_ARN }}
        aws-region: ${{ env.AWS_REGION }}

    - name: Terraform Format
      run: terraform fmt -check -recursive

    - name: Terraform Init
      run: terraform init

    - name: Terraform Validate
      run: terraform validate

    - name: Terraform Plan
      run: terraform plan -out=tfplan

    - name: Terraform Apply
      if: github.ref == 'refs/heads/main' && github.event_name == 'push'
      run: terraform apply -auto-approve tfplan
```

### Pre-commit Hooks

```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.88.0
    hooks:
      - id: terraform_fmt
      - id: terraform_validate
      - id: terraform_docs
      - id: terraform_tflint
      - id: terraform_tfsec
```

### Testing with Terratest

```go
// test/vpc_test.go
package test

import (
    "testing"
    "github.com/gruntwork-io/terratest/modules/terraform"
    "github.com/stretchr/testify/assert"
)

func TestVPCCreation(t *testing.T) {
    terraformOptions := &terraform.Options{
        TerraformDir: "../examples/vpc",
        Vars: map[string]interface{}{
            "environment": "test",
            "vpc_cidr":    "10.0.0.0/16",
        },
    }

    defer terraform.Destroy(t, terraformOptions)
    terraform.InitAndApply(t, terraformOptions)

    vpcId := terraform.Output(t, terraformOptions, "vpc_id")
    assert.NotEmpty(t, vpcId)
}
```

## Part 8: Common Patterns and Anti-Patterns

### ✅ Best Practices

```hcl
# 1. Use variables for reusability
variable "tags" {
  type = map(string)
  default = {}
}

locals {
  common_tags = merge(
    var.tags,
    {
      ManagedBy   = "Terraform"
      Environment = var.environment
    }
  )
}

# 2. Use data sources for existing resources
data "aws_vpc" "existing" {
  id = var.vpc_id
}

# 3. Explicit dependencies when needed
resource "aws_eip" "nat" {
  domain = "vpc"
  depends_on = [aws_internet_gateway.main]
}

# 4. Use lifecycle rules
resource "aws_instance" "web" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  lifecycle {
    create_before_destroy = true
    prevent_destroy       = false
    ignore_changes        = [tags["LastUpdated"]]
  }
}

# 5. Sensitive outputs
output "db_password" {
  value     = random_password.db.result
  sensitive = true
}
```

### ❌ Anti-Patterns to Avoid

```hcl
# DON'T: Hardcode values
resource "aws_instance" "web" {
  ami           = "ami-0c55b159cbfafe1f0"  # Bad
  instance_type = "t2.micro"               # Bad
}

# DO: Use variables and data sources
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
}

resource "aws_instance" "web" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
}

# DON'T: Store secrets in code
variable "db_password" {
  default = "mypassword123"  # Never do this!
}

# DO: Use secure methods
resource "random_password" "db" {
  length  = 16
  special = true
}

data "aws_secretsmanager_secret_version" "db_creds" {
  secret_id = "production/db/credentials"
}

# DON'T: Create monolithic configurations
# Single main.tf with 2000 lines

# DO: Organize by resource type or function
# networking.tf, compute.tf, database.tf, security.tf
```

## Part 9: Troubleshooting Guide

### Common Issues and Solutions

```bash
# Issue: State lock error
# Solution: Force unlock (use carefully!)
terraform force-unlock <LOCK_ID>

# Issue: Provider version conflicts
# Solution: Upgrade providers
terraform init -upgrade

# Issue: Drift detection
# Solution: Refresh and compare
terraform plan -refresh-only

# Issue: Resource already exists
# Solution: Import it
terraform import aws_instance.web i-1234567890abcdef0

# Issue: Debugging
# Solution: Enable detailed logging
export TF_LOG=DEBUG
export TF_LOG_PATH=./terraform.log
terraform apply
```

### Validation and Linting

```bash
# Format code
terraform fmt -recursive

# Validate syntax
terraform validate

# Check with tflint
tflint --init
tflint

# Security scanning with tfsec
tfsec .

# Cost estimation with Infracost
infracost breakdown --path .
```

## Part 10: Quick Reference Commands

```bash
# Initialization and setup
terraform init                    # Initialize directory
terraform init -upgrade           # Upgrade providers
terraform init -reconfigure       # Reconfigure backend

# Planning and applying
terraform plan                    # Show execution plan
terraform plan -out=tfplan        # Save plan to file
terraform apply                   # Apply changes
terraform apply tfplan            # Apply saved plan
terraform apply -auto-approve     # Skip confirmation
terraform apply -target=resource  # Target specific resource

# Destruction
terraform destroy                 # Destroy all resources
terraform destroy -target=resource # Destroy specific resource

# State management
terraform state list              # List resources in state
terraform state show resource     # Show resource details
terraform state mv old new        # Rename resource
terraform state rm resource       # Remove from state
terraform state pull              # Download remote state
terraform state push              # Upload state

# Outputs and inspection
terraform output                  # Show all outputs
terraform output name             # Show specific output
terraform show                    # Show current state
terraform graph                   # Generate dependency graph

# Workspaces
terraform workspace list          # List workspaces
terraform workspace new name      # Create workspace
terraform workspace select name   # Switch workspace
terraform workspace delete name   # Delete workspace

# Providers
terraform providers               # Show provider requirements
terraform providers lock          # Update lock file
terraform providers schema        # Show provider schemas

# Import and refresh
terraform import resource id      # Import existing resource
terraform refresh                 # Update state from real infra

# Validation and formatting
terraform validate                # Validate configuration
terraform fmt                     # Format code
terraform fmt -check              # Check formatting
terraform fmt -recursive          # Format all subdirectories

# Console and testing
terraform console                 # Interactive console
terraform test                    # Run tests (Terraform 1.6+)
```

## Part 11: Modern Features (Post-2022)

### Native Testing Framework

```hcl
# tests/vpc.tftest.hcl
run "vpc_creation" {
  command = apply

  variables {
    environment = "test"
    vpc_cidr    = "10.0.0.0/16"
  }

  assert {
    condition     = aws_vpc.main.cidr_block == "10.0.0.0/16"
    error_message = "VPC CIDR mismatch"
  }

  assert {
    condition     = length(aws_subnet.public) > 0
    error_message = "No public subnets created"
  }
}
```

### Moved Blocks (Refactoring)

```hcl
# Instead of manual state mv commands
moved {
  from = aws_instance.web
  to   = aws_instance.application
}

moved {
  from = module.vpc
  to   = module.network
}
```

### Import Blocks

```hcl
# Declarative imports (Terraform 1.5+)
import {
  to = aws_instance.existing
  id = "i-1234567890abcdef0"
}

resource "aws_instance" "existing" {
  # Configuration will be generated
}
```

### Check Blocks

```hcl
# Continuous validation
check "health_check" {
  data "http" "app_health" {
    url = "http://${aws_instance.web.public_ip}/health"
  }

  assert {
    condition     = data.http.app_health.status_code == 200
    error_message = "Application health check failed"
  }
}
```

## Part 12: Real-World Patterns

### Multi-Environment Setup

```
project/
├── environments/
│   ├── dev/
│   │   ├── main.tf
│   │   ├── backend.tf
│   │   └── terraform.tfvars
│   ├── staging/
│   │   └── ...
│   └── prod/
│       └── ...
└── modules/
    └── app-stack/
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

```hcl
# environments/dev/main.tf
module "app_stack" {
  source = "../../modules/app-stack"

  environment     = "dev"
  instance_type   = "t3.micro"
  instance_count  = 1
  enable_backups  = false
}

# environments/prod/main.tf
module "app_stack" {
  source = "../../modules/app-stack"

  environment     = "prod"
  instance_type   = "t3.large"
  instance_count  = 3
  enable_backups  = true
  backup_retention = 30
}
```

### Blue-Green Deployments

```hcl
variable "active_environment" {
  type    = string
  default = "blue"

  validation {
    condition     = contains(["blue", "green"], var.active_environment)
    error_message = "Must be blue or green"
  }
}

resource "aws_lb_target_group" "blue" {
  name     = "app-blue"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

resource "aws_lb_target_group" "green" {
  name     = "app-green"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
}

resource "aws_lb_listener_rule" "main" {
  listener_arn = aws_lb_listener.main.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = var.active_environment == "blue" ?
                       aws_lb_target_group.blue.arn :
                       aws_lb_target_group.green.arn
  }

  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}
```

## Conclusion

You should now have a solid refresh of Terraform fundamentals and modern practices. The key areas to focus on for DevOps work are:

1. **State Management**: Always use remote state with locking
2. **Modularity**: Break infrastructure into reusable modules
3. **Version Control**: Lock provider versions, commit lock files
4. **CI/CD Integration**: Automate testing and deployment
5. **Security**: Use secrets management, enable encryption
6. **Testing**: Implement validation and testing early
7. **Documentation**: Keep README files and variable descriptions current

### Next Steps

- Set up a test project using the examples above
- Explore Terraform Cloud or Terraform Enterprise for team collaboration
- Investigate policy-as-code with Sentinel or OPA
- Look into CDK for Terraform (CDKTF) for familiar programming languages
- Review your cloud provider's specific Terraform best practices

### Additional Resources

- [Terraform Documentation](https://developer.hashicorp.com/terraform/docs)
- [Terraform Registry](https://registry.terraform.io/)
- [Terraform Best Practices](https://www.terraform-best-practices.com/)
- [Gruntwork Infrastructure as Code Library](https://gruntwork.io/infrastructure-as-code-library/)

Happy Terraforming!
