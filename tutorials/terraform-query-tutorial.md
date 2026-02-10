# Tutorial: Using the `terraform query` Command

## Introduction

The `terraform query` command is part of **Terraform Search**, a feature for declarative resource discovery. It lets you find existing infrastructure resources managed outside of Terraform so you can bring them under Terraform management. You define queries in `.tfquery.hcl` files using a new `list` block, then run `terraform query` to discover matching resources.

This tutorial walks you through everything from a basic query to advanced filtering and config generation.

---

## Prerequisites

Before you begin, ensure you have the following:

- **Terraform CLI** — a version that supports the `terraform query` command (introduced in late 2025).
- **AWS credentials** configured in your environment (the examples below use the AWS provider).
- **AWS provider v6.0+** — required for `list` resource support.
- A working directory initialized with `terraform init`.

### Supported List Resource Types (AWS Provider)

At the time of writing, the AWS provider supports three list resource types:

| List Resource Type           | What It Discovers             |
|------------------------------|-------------------------------|
| `aws_instance`               | EC2 instances                 |
| `aws_iam_role`               | IAM roles                     |
| `aws_cloudwatch_log_group`   | CloudWatch log groups         |

More resource types and providers are being added over time.

---

## Step 1: Set Up Your Working Directory

Create a new directory and add a minimal `main.tf` to declare the AWS provider:

```hcl
# main.tf
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
```

Initialize the configuration:

```bash
terraform init
```

This downloads the AWS provider plugin, which is required before `terraform query` can execute.

---

## Step 2: Write Your First Query

Create a file named `search.tfquery.hcl` (the file must end with `.tfquery.hcl`). This query discovers all EC2 instances in `us-west-1`:

```hcl
# search.tfquery.hcl
provider "aws" {
  region = "us-west-1"
}

list "aws_instance" "all" {
  provider = aws
}
```

### Anatomy of the file

- **`provider` block** — Configures which provider (and region) to query against.
- **`list` block** — Defines a query. It takes two labels: the resource type (`aws_instance`) and a symbolic name (`all`). The `provider` argument is required.

---

## Step 3: Run the Query

Execute the query:

```bash
terraform query
```

Terraform reads all `.tfquery.hcl` files in the current directory and runs each `list` block. Example output:

```
list.aws_instance.all   account_id=123456789012,id=i-0835b41ff06f2b6cf,region=us-west-1   frontend
list.aws_instance.all   account_id=123456789012,id=i-0e7ad4412b60c75f5,region=us-west-1   frontend
list.aws_instance.all   account_id=123456789012,id=i-066e446260eb7f82b,region=us-west-1   backend
```

Each line shows three columns:

| Column | Meaning |
|--------|---------|
| Query address | e.g. `list.aws_instance.all` — which query produced this result |
| Identity attributes | AWS account ID, instance ID, and region |
| Name tag | The `Name` tag of the resource |

You can refine and re-run `terraform query` as many times as you need.

---

## Step 4: Generate Terraform Configuration

Once you've found the resources you want, generate `resource` and `import` blocks automatically:

```bash
terraform query -generate-config-out=discovered.tf
```

This creates a new file `discovered.tf` containing a `resource` block and an `import` block for every discovered instance. For example (truncated):

```hcl
# __generated__ by Terraform
# Please review these resources and move them into your main configuration files.

resource "aws_instance" "all_0" {
  ami           = "ami-0abcdef1234567890"
  instance_type = "t3.micro"
  # ... many more attributes ...
}

import {
  to       = aws_instance.all_0
  provider = aws
  identity = {
    account_id = "123456789012"
    id         = "i-0835b41ff06f2b6cf"
    region     = "us-west-1"
  }
}
```

> **Important:** The output file must not already exist — Terraform will not overwrite or append. The generated configuration often includes many default attribute values. Review and remove unnecessary defaults before running `terraform plan`.

---

## Step 5: Use Filters to Narrow Results

For EC2 instances, you can add `filter` blocks inside a `config` block to refine your search. Filters use the same names as the AWS EC2 `DescribeInstances` API.

### Filter by tag

Find all instances with the tag `Owner=platform-team`:

```hcl
# search.tfquery.hcl
provider "aws" {
  region = "us-west-1"
}

list "aws_instance" "platform_team" {
  provider = aws

  config {
    filter {
      name   = "tag:Owner"
      values = ["platform-team"]
    }
  }
}
```

```bash
terraform query
```

```
list.aws_instance.platform_team   account_id=123456789012,id=i-066e446260eb7f82b,region=us-west-1   backend
list.aws_instance.platform_team   account_id=123456789012,id=i-064fd00d079825559,region=us-west-1   backend
```

### Filter by instance type

```hcl
list "aws_instance" "large_instances" {
  provider = aws

  config {
    filter {
      name   = "instance-type"
      values = ["m5.xlarge", "m5.2xlarge"]
    }
  }
}
```

You can combine multiple `filter` blocks in a single `list` to further narrow results.

---

## Step 6: Limit the Number of Results

Use the `limit` argument to cap how many results are returned:

```hcl
list "aws_instance" "sample" {
  provider = aws
  limit    = 5
}
```

This is useful for large accounts where you want a quick preview before running a full query.

---

## Step 7: Query Multiple Regions with `for_each`

The `list` block supports the `for_each` and `count` meta-arguments. To search across multiple regions:

```hcl
# search.tfquery.hcl
provider "aws" {
  region = "us-west-1"  # default region
}

locals {
  regions = ["us-west-1", "us-east-1", "eu-west-1"]
}

list "aws_instance" "all" {
  for_each = toset(local.regions)

  provider = aws

  config {
    region = each.value
  }
}
```

```bash
terraform query
```

```
list.aws_instance.all["eu-west-1"]    account_id=123456789012,id=i-045d428c88b12f39e,region=eu-west-1   backup
list.aws_instance.all["us-east-1"]    account_id=123456789012,id=i-089f3a5328681f9bb,region=us-east-1   web01
list.aws_instance.all["us-east-1"]    account_id=123456789012,id=i-08298eac244d627ec,region=us-east-1   web02
list.aws_instance.all["us-west-1"]    account_id=123456789012,id=i-0835b41ff06f2b6cf,region=us-west-1   frontend
```

Results are grouped by the `for_each` key, making it easy to see which region each instance belongs to.

---

## Step 8: Use Variables for Flexibility

You can parameterize your queries with `variable` blocks. Variables defined in `.tfquery.hcl` files must also be defined in the root module.

```hcl
# search.tfquery.hcl
variable "aws_region" {
  type    = string
  default = "eu-west-1"
}

provider "aws" {
  region = var.aws_region
}

list "aws_instance" "all" {
  provider = aws
}
```

Override the default at runtime:

```bash
terraform query -var='aws_region=us-east-1'
```

You can also use `-var-file=myvars.tfvars` or rely on `terraform.tfvars` / `*.auto.tfvars` files.

---

## Step 9: Query Other Resource Types

### IAM Roles

```hcl
provider "aws" {
  region = "us-west-1"
}

list "aws_iam_role" "all" {
  provider = aws
}
```

```bash
terraform query
```

```
list.aws_iam_role.all   account_id=123456789012,name=AmazonEKSAutoClusterRole   AmazonEKSAutoClusterRole
list.aws_iam_role.all   account_id=123456789012,name=my-app-role                my-app-role
```

Note: service-linked roles are not included in the results.

### CloudWatch Log Groups

```hcl
provider "aws" {
  region = "eu-west-1"
}

list "aws_cloudwatch_log_group" "all" {
  provider = aws
}
```

```bash
terraform query
```

```
list.aws_cloudwatch_log_group.all   account_id=123456789012,name=/aws/lambda/my-function,region=eu-west-1   /aws/lambda/my-function
```

At present, `aws_iam_role` and `aws_cloudwatch_log_group` do not support additional `config` or `filter` arguments.

---

## Putting It All Together: A Complete Workflow

Here is a complete end-to-end workflow for discovering and importing EC2 instances.

### 1. Create your project

```bash
mkdir terraform-import-project && cd terraform-import-project
```

### 2. Write `main.tf`

```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
```

### 3. Write `search.tfquery.hcl`

```hcl
variable "target_region" {
  type    = string
  default = "us-east-1"
}

provider "aws" {
  region = var.target_region
}

list "aws_instance" "web_servers" {
  provider = aws

  config {
    filter {
      name   = "tag:Role"
      values = ["web"]
    }
    filter {
      name   = "instance-state-name"
      values = ["running"]
    }
  }
}
```

### 4. Initialize and query

```bash
terraform init
terraform query
```

### 5. Review, then generate config

```bash
terraform query -generate-config-out=imported.tf
```

### 6. Clean up the generated config

Open `imported.tf`, remove unnecessary default values, and adjust resource names to match your naming conventions.

### 7. Import the resources

```bash
terraform plan    # Review the import plan
terraform apply   # Execute the import
```

Your discovered resources are now managed by Terraform.

---

## Quick Reference

| Task | Command |
|------|---------|
| Run all queries | `terraform query` |
| Generate config to a file | `terraform query -generate-config-out=FILE.tf` |
| Pass a variable | `terraform query -var='region=us-east-1'` |
| Use a var file | `terraform query -var-file=prod.tfvars` |
| Output as JSON | `terraform query -json` |
| Generate config as JSON | `terraform query -generate-config=file.tf -json` |

---

## Tips and Gotchas

- **Query files are separate from your main config.** The `.tfquery.hcl` files are not processed during `terraform plan` or `terraform apply`.
- **You must run `terraform init` first.** The query command needs an initialized working directory with provider plugins installed.
- **Generated config needs cleanup.** Terraform generates every possible attribute, including defaults. Remove the noise before importing.
- **Negative filters are not supported.** You cannot query for "all instances without a certain tag" directly. As a workaround, run two queries (all instances and tagged instances) and compute the difference using `locals`.
- **The output file must be new.** The `-generate-config-out` flag will not append to or overwrite an existing file.
- **Provider support is growing.** Check your provider's documentation for newly supported `list` resource types.
