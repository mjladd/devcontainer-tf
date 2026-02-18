# Terraform Workspaces: A Hands-On Tutorial for DevOps Engineers

## Introduction

Terraform workspaces allow you to manage multiple distinct sets of infrastructure resources using the same configuration. Think of workspaces as isolated state files that share the same codebase—perfect for managing environments like `dev`, `staging`, and `production` without duplicating your Terraform code.

TF workspaces are simply a way to manage multiple state files within a single configuration. Workspaces let you switch between different states within the same configuration, providing isolated state contexts that all use the same infrastructure code, allowing for deploying the same configuration to different environments or test different variations safely.

This tutorial uses only local resources (no cloud accounts required) so you can focus entirely on understanding workspaces.

---

## Why Use Workspaces?

Workspaces solve a common problem: **How do I use the same Terraform configuration to manage multiple environments?**

Without workspaces, you might:
- Duplicate entire directories for each environment
- Use complex variable files and manual state management
- Risk accidentally applying dev changes to production

With workspaces, you get:
- **Isolated state** — Each workspace has its own `.tfstate` file
- **Shared configuration** — One codebase, multiple environments
- **Simple switching** — Change environments with a single command
- **Built-in context** — Access the current workspace name via `terraform.workspace`

---

## When to Use Workspaces

### Good Use Cases

| Scenario | Why Workspaces Work |
|----------|---------------------|
| Dev/Staging/Prod environments | Same infrastructure, different scales or settings |
| Feature branch testing | Spin up isolated environments for testing |
| Multi-tenant deployments | Same app structure per customer |
| Personal sandboxes | Each team member gets their own environment |

### When NOT to Use Workspaces

Workspaces are **not** ideal when:

- Environments have **fundamentally different architectures** (use separate root modules instead)
- You need **different providers or backends** per environment
- You want **strict access control** between environments (state files are in the same backend)
- Teams manage environments **independently** (separate repos may be better)

---

## Prerequisites

Before starting, ensure you have:

```bash
# Check Terraform is installed
terraform version

# You should see output like:
# Terraform v1.x.x
```

If not installed, download from [terraform.io](https://www.terraform.io/downloads).

---

## Part 1: Understanding the Default Workspace

Every Terraform configuration starts with a workspace called `default`. Let's explore this.

### Step 1.1: Create a Project Directory

```bash
mkdir terraform-workspace-lab
cd terraform-workspace-lab
```

### Step 1.2: Create a Basic Configuration

Create a file named `main.tf`:

```hcl
# main.tf

terraform {
  required_version = ">= 1.0.0"
}

# Output the current workspace name
output "current_workspace" {
  value       = terraform.workspace
  description = "The name of the current Terraform workspace"
}
```

### Step 1.3: Initialize and Apply

```bash
terraform init
terraform apply -auto-approve
```

You'll see:

```
Apply complete! Resources: 0 added, 0 changed, 0 destroyed.

Outputs:

current_workspace = "default"
```

### Step 1.4: List Workspaces

```bash
terraform workspace list
```

Output:

```
* default
```

The `*` indicates your current workspace.

---

## Part 2: Creating and Switching Workspaces

Now let's create environment-specific workspaces.

### Step 2.1: Create New Workspaces

```bash
# Create a 'dev' workspace
terraform workspace new dev

# Create a 'staging' workspace
terraform workspace new staging

# Create a 'prod' workspace
terraform workspace new prod
```

Each command automatically switches to the newly created workspace.

### Step 2.2: List All Workspaces

```bash
terraform workspace list
```

Output:

```
  default
  dev
  staging
* prod
```

### Step 2.3: Switch Between Workspaces

```bash
# Switch to dev
terraform workspace select dev

# Verify
terraform workspace show
```

Output: `dev`

---

## Part 3: Using Workspaces with Local Files

Let's create a practical example where each workspace generates environment-specific configuration files.

### Step 3.1: Update main.tf

Replace your `main.tf` with:

```hcl
# main.tf

terraform {
  required_version = ">= 1.0.0"
}

# Define environment-specific settings
locals {
  # Map workspace names to environment configurations
  env_config = {
    default = {
      log_level     = "DEBUG"
      instance_count = 1
      feature_flags = ["debug_mode"]
    }
    dev = {
      log_level     = "DEBUG"
      instance_count = 1
      feature_flags = ["debug_mode", "experimental_feature"]
    }
    staging = {
      log_level     = "INFO"
      instance_count = 2
      feature_flags = ["experimental_feature"]
    }
    prod = {
      log_level     = "WARN"
      instance_count = 5
      feature_flags = []
    }
  }

  # Get config for current workspace (fallback to default if workspace not defined)
  current_config = lookup(local.env_config, terraform.workspace, local.env_config["default"])
}

# Create an environment-specific configuration file
resource "local_file" "app_config" {
  filename = "${path.module}/output/${terraform.workspace}/app.config"

  content = <<-EOT
    # Application Configuration
    # Environment: ${terraform.workspace}
    # Generated by Terraform - Do not edit manually

    ENVIRONMENT=${upper(terraform.workspace)}
    LOG_LEVEL=${local.current_config.log_level}
    INSTANCE_COUNT=${local.current_config.instance_count}
    FEATURE_FLAGS=${join(",", local.current_config.feature_flags)}
  EOT

  file_permission = "0644"
}

# Create a JSON config file for the application
resource "local_file" "app_config_json" {
  filename = "${path.module}/output/${terraform.workspace}/config.json"

  content = jsonencode({
    environment    = terraform.workspace
    log_level      = local.current_config.log_level
    instance_count = local.current_config.instance_count
    feature_flags  = local.current_config.feature_flags
    generated_at   = timestamp()
  })

  file_permission = "0644"
}

# Outputs
output "workspace" {
  value = terraform.workspace
}

output "config_file_path" {
  value = local_file.app_config.filename
}

output "environment_settings" {
  value = local.current_config
}
```

### Step 3.2: Apply to Each Workspace

```bash
# Apply to dev
terraform workspace select dev
terraform apply -auto-approve

# Apply to staging
terraform workspace select staging
terraform apply -auto-approve

# Apply to prod
terraform workspace select prod
terraform apply -auto-approve
```

### Step 3.3: Examine the Results

```bash
# View the directory structure
find output -type f

# Compare configurations
echo "=== DEV CONFIG ==="
cat output/dev/app.config

echo -e "\n=== STAGING CONFIG ==="
cat output/staging/app.config

echo -e "\n=== PROD CONFIG ==="
cat output/prod/app.config
```

You'll see each environment has its own configuration with appropriate settings.

---

## Part 4: Using the Null Provider for Workflow Simulation

The `null_resource` is perfect for simulating deployment workflows without real infrastructure.

### Step 4.1: Add Null Provider Configuration

Create `deployment.tf`:

```hcl
# deployment.tf

terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

# Simulate a deployment process with environment-specific behavior
resource "null_resource" "deployment" {
  # Re-run when configuration changes
  triggers = {
    config_hash = sha256(local_file.app_config.content)
    workspace   = terraform.workspace
  }

  # Simulate pre-deployment checks
  provisioner "local-exec" {
    command = <<-EOT
      echo "=========================================="
      echo "DEPLOYMENT STARTED"
      echo "=========================================="
      echo "Environment: ${terraform.workspace}"
      echo "Timestamp: $(date)"
      echo ""
      echo "Running pre-deployment checks..."
      sleep 1
    EOT
  }

  # Simulate the deployment based on environment
  provisioner "local-exec" {
    command = <<-EOT
      echo "Deploying ${local.current_config.instance_count} instance(s)..."

      %{if terraform.workspace == "prod"}
      echo "⚠️  PRODUCTION DEPLOYMENT - Extra validation enabled"
      echo "Performing extended health checks..."
      sleep 2
      %{endif}

      %{if contains(local.current_config.feature_flags, "experimental_feature")}
      echo "🧪 Experimental feature flag detected - enabling feature toggles"
      %{endif}

      echo ""
      echo "✅ Deployment complete for ${terraform.workspace}!"
      echo "=========================================="
    EOT
  }
}

# Simulate a health check that runs after deployment
resource "null_resource" "health_check" {
  depends_on = [null_resource.deployment]

  triggers = {
    deployment_id = null_resource.deployment.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "Running post-deployment health check for ${terraform.workspace}..."

      # Simulate checking each instance
      for i in $(seq 1 ${local.current_config.instance_count}); do
        echo "  Instance $i: healthy ✓"
      done

      echo "All instances healthy!"
    EOT
  }
}

output "deployment_id" {
  value       = null_resource.deployment.id
  description = "Unique identifier for this deployment"
}
```

### Step 4.2: Reinitialize and Apply

```bash
# Reinitialize to get the null provider
terraform init

# Apply to see the simulated deployment
terraform workspace select dev
terraform apply -auto-approve
```

You'll see the simulated deployment process with dev-specific behavior.

### Step 4.3: Compare Deployment Behavior

```bash
# Try production - notice the extra validation
terraform workspace select prod
terraform apply -auto-approve
```

---

## Part 5: Managing State Files

Understanding how workspaces manage state is crucial.

### Step 5.1: Examine State File Structure

```bash
# List all state-related files
ls -la terraform.tfstate.d/
ls -la terraform.tfstate.d/*/
```

You'll see:

```
terraform.tfstate.d/
├── dev/
│   └── terraform.tfstate
├── staging/
│   └── terraform.tfstate
└── prod/
    └── terraform.tfstate
```

Each workspace has its own isolated state file.

### Step 5.2: Compare State Contents

```bash
# View resources in dev
terraform workspace select dev
terraform state list

# View resources in prod
terraform workspace select prod
terraform state list
```

Both show the same resource types, but they're completely independent.

---

## Part 6: Conditional Resources Based on Workspace

Sometimes you need resources to exist only in certain environments.

### Step 6.1: Add Conditional Resources

Create `conditional.tf`:

```hcl
# conditional.tf

# Debug file only exists in non-production environments
resource "local_file" "debug_config" {
  count = terraform.workspace != "prod" ? 1 : 0

  filename = "${path.module}/output/${terraform.workspace}/debug.conf"
  content  = <<-EOT
    # Debug Configuration (${terraform.workspace} only)
    VERBOSE_LOGGING=true
    STACK_TRACES=true
    DEBUG_PORT=9999
  EOT
}

# Production-only monitoring configuration
resource "local_file" "monitoring_config" {
  count = terraform.workspace == "prod" ? 1 : 0

  filename = "${path.module}/output/${terraform.workspace}/monitoring.conf"
  content  = <<-EOT
    # Production Monitoring Configuration
    METRICS_ENABLED=true
    ALERTING_ENABLED=true
    PAGERDUTY_INTEGRATION=true
    RETENTION_DAYS=90
  EOT
}

# Null resource that only runs in staging (for integration tests)
resource "null_resource" "integration_tests" {
  count = terraform.workspace == "staging" ? 1 : 0

  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo "🧪 Running integration tests (staging only)..."
      echo "  Test 1: API connectivity... PASS"
      echo "  Test 2: Database migration... PASS"
      echo "  Test 3: Cache warming... PASS"
      echo "Integration tests complete!"
    EOT
  }
}

output "debug_enabled" {
  value = terraform.workspace != "prod"
}

output "environment_type" {
  value = terraform.workspace == "prod" ? "production" : "non-production"
}
```

### Step 6.2: Apply and Observe Differences

```bash
# In dev - should have debug.conf
terraform workspace select dev
terraform apply -auto-approve
ls output/dev/

# In staging - should have debug.conf AND run integration tests
terraform workspace select staging
terraform apply -auto-approve
ls output/staging/

# In prod - should have monitoring.conf, NO debug.conf
terraform workspace select prod
terraform apply -auto-approve
ls output/prod/
```

---

## Part 7: Variables and Workspaces

Combine variables with workspace-aware defaults for flexibility.

### Step 7.1: Create variables.tf

```hcl
# variables.tf

variable "base_domain" {
  description = "Base domain for the application"
  type        = string
  default     = "example.com"
}

variable "owner" {
  description = "Team or person responsible for this infrastructure"
  type        = string
  default     = "platform-team"
}

variable "cost_center" {
  description = "Cost center for billing"
  type        = string
  default     = "engineering"
}

# Workspace-aware computed values
locals {
  # Construct environment-specific domain
  app_domain = terraform.workspace == "prod" ? "app.${var.base_domain}" : "${terraform.workspace}.app.${var.base_domain}"

  # Standard tags that include workspace information
  common_tags = {
    Environment = terraform.workspace
    ManagedBy   = "terraform"
    Owner       = var.owner
    CostCenter  = var.cost_center
    Workspace   = terraform.workspace
  }
}
```

### Step 7.2: Create a Tags File

Add to `main.tf` or create `tags.tf`:

```hcl
# tags.tf

resource "local_file" "tags_manifest" {
  filename = "${path.module}/output/${terraform.workspace}/tags.json"

  content = jsonencode({
    resource_tags = local.common_tags
    domain        = local.app_domain
    metadata = {
      terraform_version = ">=1.0"
      last_updated      = timestamp()
    }
  })
}

output "app_domain" {
  value = local.app_domain
}

output "resource_tags" {
  value = local.common_tags
}
```

### Step 7.3: Apply with Custom Variables

```bash
terraform workspace select dev
terraform apply -auto-approve \
  -var="base_domain=mycompany.io" \
  -var="owner=alice"

cat output/dev/tags.json | jq .
```

---

## Part 8: Workspace Best Practices

### 8.1: Use Workspace-Specific tfvars Files

Create environment-specific variable files:

```bash
# Create tfvars for each environment
cat > dev.tfvars << 'EOF'
base_domain = "dev.internal"
owner       = "dev-team"
cost_center = "development"
EOF

cat > prod.tfvars << 'EOF'
base_domain = "production.company.com"
owner       = "sre-team"
cost_center = "production-infrastructure"
EOF
```

Apply using the matching tfvars:

```bash
terraform workspace select dev
terraform apply -var-file="${terraform.workspace}.tfvars" -auto-approve
```

### 8.2: Create a Workspace Selection Script

Create `workspace-apply.sh`:

```bash
#!/bin/bash
# workspace-apply.sh - Safely apply Terraform to a specific workspace

set -e

WORKSPACE=${1:-$(terraform workspace show)}
TFVARS_FILE="${WORKSPACE}.tfvars"

echo "🔄 Switching to workspace: ${WORKSPACE}"
terraform workspace select "${WORKSPACE}" || terraform workspace new "${WORKSPACE}"

echo "📋 Current workspace: $(terraform workspace show)"

if [ -f "${TFVARS_FILE}" ]; then
    echo "📁 Using variables file: ${TFVARS_FILE}"
    terraform apply -var-file="${TFVARS_FILE}" "${@:2}"
else
    echo "⚠️  No ${TFVARS_FILE} found, using defaults"
    terraform apply "${@:2}"
fi
```

Make it executable:

```bash
chmod +x workspace-apply.sh
./workspace-apply.sh dev -auto-approve
```

### 8.3: Protect Production

Add a confirmation for production applies. Create `protection.tf`:

```hcl
# protection.tf

# This null_resource acts as a gate for production deployments
resource "null_resource" "production_gate" {
  count = terraform.workspace == "prod" ? 1 : 0

  provisioner "local-exec" {
    command = <<-EOT
      echo ""
      echo "╔══════════════════════════════════════════════════════════╗"
      echo "║  ⚠️   PRODUCTION DEPLOYMENT INITIATED   ⚠️                ║"
      echo "║                                                          ║"
      echo "║  This deployment will affect production infrastructure.  ║"
      echo "║  Ensure you have:                                        ║"
      echo "║    ✓ Reviewed the plan output                            ║"
      echo "║    ✓ Obtained necessary approvals                        ║"
      echo "║    ✓ Verified rollback procedures                        ║"
      echo "╚══════════════════════════════════════════════════════════╝"
      echo ""
    EOT
  }
}
```

---

## Part 9: Cleanup

### 9.1: Destroy Resources in Each Workspace

```bash
# Destroy in each workspace
for ws in dev staging prod; do
  terraform workspace select $ws
  terraform destroy -auto-approve
done
```

### 9.2: Delete Workspaces

```bash
# Switch to default first (can't delete current workspace)
terraform workspace select default

# Delete other workspaces
terraform workspace delete dev
terraform workspace delete staging
terraform workspace delete prod
```

### 9.3: Clean Up Files

```bash
cd ..
rm -rf terraform-workspace-lab
```

---

## Quick Reference

| Command | Description |
|---------|-------------|
| `terraform workspace list` | List all workspaces |
| `terraform workspace show` | Show current workspace |
| `terraform workspace new <name>` | Create and switch to new workspace |
| `terraform workspace select <name>` | Switch to existing workspace |
| `terraform workspace delete <name>` | Delete a workspace |
| `terraform.workspace` | Reference current workspace in HCL |

---

## Summary

You've learned how to:

1. **Create and manage workspaces** — Isolate state for different environments
2. **Use `terraform.workspace`** — Make configurations environment-aware
3. **Conditional resources** — Deploy different resources per environment
4. **Local providers** — Practice safely without cloud costs
5. **Best practices** — Protect production, use tfvars, automate safely

Workspaces are a powerful tool when used appropriately. They excel at managing similar environments with the same configuration. For more complex scenarios with different architectures or strict isolation requirements, consider separate root modules or Terragrunt.

---

## Next Steps

- Explore remote backends (S3, Azure Blob, GCS) with workspace support
- Investigate Terragrunt for more complex multi-environment setups
- Set up CI/CD pipelines with workspace-aware deployments
- Implement workspace-based access controls with Terraform Cloud/Enterprise
