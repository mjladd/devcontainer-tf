# Terraform with AWS: A practical guide for junior DevOps engineers

**The fastest path to Terraform proficiency combines three elements: a well-configured IDE with the HashiCorp Terraform extension, systematic use of AWS CLI for debugging, and a disciplined write-plan-apply workflow.**

## Table of Contents

- [Essential IDE setup for Terraform development](#essential-ide-setup-for-terraform-development)
- [When to use IDE autocomplete versus documentation](#when-to-use-ide-autocomplete-versus-documentation)
- [Tools for exploring AWS APIs when writing Terraform](#tools-for-exploring-aws-apis-when-writing-terraform)
- [Why terraform plan fails and how to fix it](#why-terraform-plan-fails-and-how-to-fix-it)
- [Debugging with TF_LOG and AWS CLI inspection](#debugging-with-tf_log-and-aws-cli-inspection)
- [A systematic debugging workflow when plans fail](#a-systematic-debugging-workflow-when-plans-fail)
- [Learning best practices for long-term success](#learning-best-practices-for-long-term-success)
- [Conclusion](#conclusion)

Junior engineers often struggle because they rely too heavily on either documentation or IDE tooling alone—effective learning requires both. The Terraform Registry documentation explains *how* to configure resources correctly, while IDE autocomplete helps you discover *what's available*. When plans fail, AWS CLI commands let you inspect actual infrastructure state and verify permissions, making it your most powerful debugging companion.

This guide covers the essential tools, workflows, and debugging techniques that will accelerate your learning curve while building production-quality habits from day one.

## Essential IDE setup for Terraform development

The **HashiCorp Terraform Extension for VS Code** is the cornerstone of modern Terraform development, with over 5.9 million installs. It bundles terraform-ls (the Terraform Language Server) and provides IntelliSense, code navigation, and integrated formatting. After running `terraform init` in your project folder, the extension automatically downloads provider schemas and enables context-aware autocomplete for all AWS resources.

To configure VS Code optimally, add these settings to your `settings.json`:

```json
{
  "terraform.experimentalFeatures.prefillRequiredFields": true,
  "terraform.codelens.referenceCount": true,
  "[terraform]": {
    "editor.defaultFormatter": "hashicorp.terraform",
    "editor.formatOnSave": true,
    "editor.hover.enabled": true,
    "editor.parameterHints.enabled": true,
    "terraform.languageServer.enable": true
  }
}
```

Beyond the core extension, install **TFLint** for linting that catches errors `terraform validate` misses—like invalid EC2 instance types or deprecated syntax. The AWS plugin for TFLint adds checks specific to AWS resources. For security scanning, **Trivy** (which now incorporates tfsec) identifies open security groups, hardcoded secrets, and overly permissive IAM roles before they reach production.

Your pre-commit workflow should run these commands in sequence: `terraform fmt -check` for formatting, `tflint` for linting, `trivy config .` for security, `terraform_docs` for documentation, `terraform validate` for configuration validation, then `terraform plan` to preview changes.

Running `infracost breakdown --path .` is also worth exploring.

**The Terraform Language Server (terraform-ls)** provides intelligent code completion, hover documentation, and diagnostics as you write `.tf` files. When you type `resource "aws_` and pause, it will suggest all available AWS resource types. When you're inside a resource block and type an argument name, it will tell you the expected type and whether it's required.

## When to use IDE autocomplete versus documentation

IDE autocomplete excels at discovering what's available—typing `aws_` reveals all AWS resource types, and inside a resource block, you see all arguments with their types marked as required or optional. This makes autocomplete ideal for quick reference, finding argument names, and exploring unfamiliar resources.

**Consult documentation when you need to understand valid values, complex configurations, or resource relationships.** For example, autocomplete tells you `instance_type` is a required string, but the Terraform Registry documentation at registry.terraform.io/providers/hashicorp/aws/latest/docs lists valid instance types, explains pricing implications, and shows nested block configurations like `ebs_block_device`.

The documentation structure follows a consistent pattern: Example Usage (copy and modify these), Argument Reference (inputs you configure), and Attributes Reference (outputs available after creation). Understanding the difference between arguments and attributes is crucial—attributes marked "(known after apply)" in plan output can only be referenced after the resource exists.

For first-time use of any resource, read the documentation. For familiar resources where you just need a syntax reminder, autocomplete suffices.

## Tools for exploring AWS APIs when writing Terraform

Terraform resources are thin wrappers around privider API calls.

The AWS CLI's describe commands are invaluable for understanding what Terraform needs to configure. Running `aws ec2 describe-instances` shows every attribute an instance has—these map directly to Terraform resource attributes with naming converted from CamelCase to snake_case (InstanceType becomes instance_type).

Key exploration commands include:

```bash
# Discover existing resources and their attributes
aws ec2 describe-instances --query 'Reservations[].Instances[]'
aws ec2 describe-vpcs --vpc-ids vpc-12345678
aws s3api list-buckets
aws iam get-role --role-name my-role

# Generate JSON skeleton showing all available parameters
aws ec2 run-instances --generate-cli-skeleton
```

After you've applied a configuration, use `terraform state show <resource_address>` to see the complete state of the resource, including all the attributes that were computed by the provider. This shows you what information is available for referencing in other resources.

```bash
# See the full state of our VPC, including computed attributes
terraform state show aws_vpc.main

# This reveals attributes like:
# - arn (the Amazon Resource Name)
# - default_route_table_id (automatically created by AWS)
# - default_security_group_id (also created automatically)
# - main_route_table_id (the main route table association)
```

**AWS CloudShell** provides a browser-based terminal with pre-installed AWS CLI and pre-authenticated credentials—perfect for quick API exploration without local setup. For reverse-engineering existing infrastructure, **Terraformer** and **Former2** generate Terraform code from AWS resources, which helps you understand correct syntax for complex configurations.

The Terraform Registry maps AWS services to resources predictably: EC2 instances become `aws_instance`, S3 buckets become `aws_s3_bucket`, Lambda functions become `aws_lambda_function`. When you can't find a resource, search the Registry for the AWS service name.

### Terraform Console

`terraform console` lets you interactively evaluate expressions against your state. You can explore complex data structures, test interpolation syntax, and understand how `for` expressions work. This is invaluable for learning Terraform's expression language.

## Why terraform plan fails and how to fix it

Plan failures typically fall into five categories: missing arguments, permission errors, dependency issues, provider problems, or state mismatches. Error messages include the resource address, file name, and line number—read these carefully before debugging deeper.

**Permission errors** are the most common frustration for beginners. When you see `AccessDenied: User is not authorized to perform`, first verify your identity:

```bash
aws sts get-caller-identity
```

For encoded authorization messages, decode them:

```bash
aws sts decode-authorization-message --encoded-message '<encoded-message>' \
    --query DecodedMessage --output text
```

**State mismatches** occur when infrastructure changes outside Terraform. Use `terraform state list` to see managed resources and `terraform state show aws_instance.example` to view specific resource details. When state conflicts with reality, `terraform refresh` synchronizes state with actual infrastructure, and `terraform import` brings existing resources under management.

For **provider version issues**, pin versions explicitly to prevent breaking changes:

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

## Debugging with TF_LOG and AWS CLI inspection

When error messages aren't sufficient, enable Terraform debug logging. Start with DEBUG level, which shows provider and backend interactions without overwhelming detail:

```bash
export TF_LOG=DEBUG
export TF_LOG_PATH="./terraform-debug.log"
terraform plan
```

Only escalate to TRACE (which includes full HTTP request/response bodies) when DEBUG doesn't reveal the issue. Remember to unset these variables when debugging is complete.

**AWS CLI is your verification layer** for comparing what Terraform expects versus what actually exists. A practical debugging workflow:

```bash
# 1. Check Terraform's view of the resource
terraform state show aws_instance.example

# 2. Check AWS's actual state
aws ec2 describe-instances --instance-ids i-1234567890abcdef0

# 3. Compare key attributes: instance_type, ami, security_groups, tags
```

For permission issues specifically, simulate whether a principal can perform an action:

```bash
aws iam simulate-principal-policy \
    --policy-source-arn arn:aws:iam::123456789012:user/terraform \
    --action-names "ec2:RunInstances" "s3:PutObject" \
    --resource-arns "*"
```

**AWS CloudTrail** shows the actual API calls Terraform makes. In the Console, navigate to CloudTrail → Event History, filter by timeframe around your error, and look for events with error codes. Via CLI: `aws cloudtrail lookup-events | jq '.Events[] | select(.ErrorCode=="AccessDenied")'`.

## A systematic debugging workflow when plans fail

Follow this sequence to efficiently diagnose failures:

1. **Read the error message** — note resource address, line number, and error type
2. **Run terraform validate** — catches syntax and configuration errors quickly
3. **Verify credentials** — `aws sts get-caller-identity` confirms you're using the right account
4. **Compare state vs reality** — use `terraform state show` alongside `aws describe-*` commands
5. **Enable DEBUG logging** — look for ERROR or WARN entries in the log file
6. **Check CloudTrail** — review recent API calls for AccessDenied or other failures
7. **Apply targeted fixes** — syntax errors need config changes, permission errors need IAM updates, state mismatches may need `terraform import` or `terraform state rm`

## Learning best practices for long-term success

**The write-plan-apply cycle is your foundation.** Make `terraform fmt`, `terraform validate`, and `terraform plan` habitual commands you run before every apply. Never skip reviewing plan output—it shows exactly what will be created, modified, or destroyed.

Start with simple resources: an EC2 instance with tags, then add a security group (learning dependencies), then introduce variables for reusability. Progress to VPCs with subnets, then refactor into modules, then configure remote state with S3 and DynamoDB locking. This progression builds understanding incrementally.

**Create a dedicated AWS sandbox account** under AWS Organizations for learning. Implement Service Control Policies to restrict regions and instance types, set budget alerts, and use AWS Free Tier resources. Never experiment in production accounts.

For version control, commit all `.tf` files and `.terraform.lock.hcl`, but never commit state files, the `.terraform/` directory, or `*.tfvars` files containing secrets. Use remote backends from the start to build production-ready habits.

The HashiCorp Learn tutorials at developer.hashicorp.com/terraform/tutorials/aws-get-started provide excellent structured learning, and "Terraform: Up and Running" by Yevgeniy Brikman offers the deepest treatment of real-world patterns. The AWS Prescriptive Guidance at docs.aws.amazon.com/prescriptive-guidance/latest/terraform-aws-provider-best-practices covers security and architecture recommendations specific to the AWS provider.

## Terraform Review

### HCL Syntax Review

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

### Review of Key Files

**main.tf**: Primary configuration
**variables.tf**: Input variable declarations
**outputs.tf**: Output value declarations
**terraform.tfvars**: Variable value assignments (don't commit secrets!)
**.terraform.lock.hcl**: Dependency lock file (commit this)

### Advanced Features

#### Terraform Functions

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

#### For Expressions and Dynamic Blocks

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

#### Count vs For_Each

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



## Conclusion

Effective Terraform development requires mastering three interconnected skills: IDE tooling for efficient coding, documentation for understanding resource configuration, and CLI debugging for troubleshooting failures. The HashiCorp Terraform extension provides the foundation, but **AWS CLI proficiency separates proficient engineers from those who struggle** with mysterious plan failures.

Build the habit of running `terraform plan` before every apply, use remote state from your first team project, and progress from simple resources to modules systematically. When plans fail, follow the debugging workflow: verify credentials, compare state to reality, enable logging, check CloudTrail. This methodical approach transforms frustrating errors into learning opportunities that deepen your understanding of both Terraform and AWS.
