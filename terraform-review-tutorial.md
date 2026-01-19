# Terraform Review Tutorial for DevOps Engineers

A hands-on refresher for those returning to Terraform after time away. This tutorial uses `null_resource` and `local-exec` provisioners exclusively, so you can run everything locally without cloud credentials.

## Prerequisites

- Terraform installed (v1.0+)
- A terminal
- Basic familiarity with Terraform concepts

Verify your installation:

```bash
terraform version
```

---

## 1. Project Setup and Initialization

Create a working directory and your first configuration file:

```bash
mkdir terraform-refresher && cd terraform-refresher
```

Create `main.tf`:

```hcl
terraform {
  required_version = ">= 1.0.0"
  
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}
```

Initialize the project:

```bash
terraform init
```

This downloads the null provider and creates the `.terraform` directory and lock file.

---

## 2. Your First Null Resource

The `null_resource` doesn't manage real infrastructure—it's a container for provisioners and triggers. Perfect for running scripts or coordinating actions.

Add to `main.tf`:

```hcl
resource "null_resource" "hello" {
  provisioner "local-exec" {
    command = "echo 'Hello from Terraform!'"
  }
}
```

Run:

```bash
terraform plan
terraform apply
```

Type `yes` when prompted. You'll see your echo output in the terminal.

---

## 3. Variables and Outputs

Create `variables.tf`:

```hcl
variable "environment" {
  description = "Deployment environment name"
  type        = string
  default     = "development"
}

variable "app_name" {
  description = "Application name"
  type        = string
}

variable "features" {
  description = "List of enabled features"
  type        = list(string)
  default     = ["logging", "metrics"]
}

variable "config" {
  description = "Application configuration"
  type = object({
    port    = number
    debug   = bool
    workers = number
  })
  default = {
    port    = 8080
    debug   = true
    workers = 4
  }
}
```

Create `outputs.tf`:

```hcl
output "environment" {
  description = "Current environment"
  value       = var.environment
}

output "app_summary" {
  description = "Application summary"
  value       = "${var.app_name} running on port ${var.config.port}"
}
```

Create `terraform.tfvars`:

```hcl
app_name    = "my-service"
environment = "staging"
features    = ["logging", "metrics", "tracing"]
```

Update `main.tf` to use variables:

```hcl
resource "null_resource" "app_info" {
  provisioner "local-exec" {
    command = "echo 'Deploying ${var.app_name} to ${var.environment}'"
  }
}
```

Apply and observe the outputs:

```bash
terraform apply
```

---

## 4. Triggers and Resource Recreation

Triggers let you control when a null_resource runs again. Without triggers, it only runs once.

```hcl
resource "null_resource" "versioned" {
  triggers = {
    version    = "1.2.0"
    updated_at = timestamp()  # Forces run every apply
  }

  provisioner "local-exec" {
    command = "echo 'Version: ${self.triggers.version}'"
  }
}
```

A more practical example—re-run only when configuration changes:

```hcl
resource "null_resource" "config_deploy" {
  triggers = {
    config_hash = sha256(jsonencode(var.config))
  }

  provisioner "local-exec" {
    command = "echo 'Config changed, redeploying with ${var.config.workers} workers'"
  }
}
```

---

## 5. Dependencies and Ordering

Terraform builds a dependency graph automatically, but sometimes you need explicit control.

```hcl
resource "null_resource" "step_1" {
  provisioner "local-exec" {
    command = "echo 'Step 1: Preparation' && sleep 1"
  }
}

resource "null_resource" "step_2" {
  depends_on = [null_resource.step_1]

  provisioner "local-exec" {
    command = "echo 'Step 2: Execution'"
  }
}

resource "null_resource" "step_3" {
  depends_on = [null_resource.step_2]

  provisioner "local-exec" {
    command = "echo 'Step 3: Cleanup'"
  }
}
```

Visualize the graph:

```bash
terraform graph | dot -Tpng > graph.png
# Or just view the text representation
terraform graph
```

---

## 6. Count and For Each

### Using count

```hcl
variable "server_count" {
  default = 3
}

resource "null_resource" "servers" {
  count = var.server_count

  provisioner "local-exec" {
    command = "echo 'Provisioning server-${count.index}'"
  }
}

output "server_ids" {
  value = null_resource.servers[*].id
}
```

### Using for_each with a list

```hcl
variable "regions" {
  default = ["us-east", "us-west", "eu-central"]
}

resource "null_resource" "regional_deploy" {
  for_each = toset(var.regions)

  provisioner "local-exec" {
    command = "echo 'Deploying to ${each.key}'"
  }
}
```

### Using for_each with a map

```hcl
variable "services" {
  default = {
    api = {
      port     = 8080
      replicas = 3
    }
    worker = {
      port     = 9090
      replicas = 5
    }
    cache = {
      port     = 6379
      replicas = 2
    }
  }
}

resource "null_resource" "service_deploy" {
  for_each = var.services

  triggers = {
    config = jsonencode(each.value)
  }

  provisioner "local-exec" {
    command = "echo 'Service: ${each.key}, Port: ${each.value.port}, Replicas: ${each.value.replicas}'"
  }
}

output "deployed_services" {
  value = { for k, v in null_resource.service_deploy : k => v.id }
}
```

---

## 7. Local Values and Expressions

Create `locals.tf`:

```hcl
locals {
  # Simple values
  project_prefix = "${var.app_name}-${var.environment}"
  
  # Conditional logic
  is_production = var.environment == "production"
  log_level     = local.is_production ? "warn" : "debug"
  
  # Computed lists
  all_tags = concat(
    ["managed-by:terraform"],
    var.features,
    local.is_production ? ["critical"] : []
  )
  
  # Map transformation
  service_endpoints = {
    for name, config in var.services :
    name => "http://localhost:${config.port}"
  }
}

resource "null_resource" "show_locals" {
  provisioner "local-exec" {
    command = <<-EOT
      echo "Project: ${local.project_prefix}"
      echo "Production: ${local.is_production}"
      echo "Log Level: ${local.log_level}"
      echo "Tags: ${join(", ", local.all_tags)}"
    EOT
  }
}

output "endpoints" {
  value = local.service_endpoints
}
```

---

## 8. Working with Files and Templates

### Reading files

```hcl
resource "null_resource" "file_reader" {
  provisioner "local-exec" {
    command = "echo 'Config content hash: ${sha256(file("terraform.tfvars"))}'"
  }
}
```

### Using templatefile

Create `templates/config.tpl`:

```
Application: ${app_name}
Environment: ${environment}
Workers: ${workers}

Features:
%{ for feature in features ~}
  - ${feature}
%{ endfor ~}
```

Use it in your configuration:

```hcl
resource "null_resource" "templated_config" {
  triggers = {
    template_hash = sha256(templatefile("templates/config.tpl", {
      app_name    = var.app_name
      environment = var.environment
      workers     = var.config.workers
      features    = var.features
    }))
  }

  provisioner "local-exec" {
    command = <<-EOT
      cat << 'EOF'
      ${templatefile("templates/config.tpl", {
        app_name    = var.app_name
        environment = var.environment
        workers     = var.config.workers
        features    = var.features
      })}
      EOF
    EOT
  }
}
```

---

## 9. Modules

Modules encapsulate reusable configuration. Create a simple module:

```bash
mkdir -p modules/deployment
```

Create `modules/deployment/main.tf`:

```hcl
variable "name" {
  type = string
}

variable "version" {
  type    = string
  default = "latest"
}

variable "replicas" {
  type    = number
  default = 1
}

resource "null_resource" "deploy" {
  count = var.replicas

  triggers = {
    version = var.version
  }

  provisioner "local-exec" {
    command = "echo 'Deploying ${var.name}:${var.version} - replica ${count.index + 1}/${var.replicas}'"
  }
}

output "deployment_ids" {
  value = null_resource.deploy[*].id
}

output "deployment_name" {
  value = var.name
}
```

Use the module in your root `main.tf`:

```hcl
module "api_deployment" {
  source   = "./modules/deployment"
  name     = "api-service"
  version  = "2.1.0"
  replicas = 3
}

module "worker_deployment" {
  source   = "./modules/deployment"
  name     = "worker-service"
  version  = "1.5.0"
  replicas = 2
}

output "api_ids" {
  value = module.api_deployment.deployment_ids
}
```

Re-initialize to load the module:

```bash
terraform init
terraform apply
```

---

## 10. State Management

### Inspecting state

```bash
# List all resources
terraform state list

# Show details of a specific resource
terraform state show null_resource.hello

# Pull the entire state as JSON
terraform state pull | jq .
```

### Moving and removing resources

```bash
# Rename a resource in state (useful for refactoring)
terraform state mv null_resource.hello null_resource.greeting

# Remove a resource from state (doesn't destroy it)
terraform state rm null_resource.servers[0]

# Import existing resource (if you had real infrastructure)
# terraform import null_resource.example <id>
```

### Workspaces for environment isolation

```bash
# List workspaces
terraform workspace list

# Create and switch to a new workspace
terraform workspace new production
terraform workspace new staging

# Switch between workspaces
terraform workspace select staging

# Use workspace in configuration
# terraform.workspace gives current workspace name
```

Add workspace-aware configuration:

```hcl
locals {
  workspace_config = {
    default = {
      replicas = 1
      debug    = true
    }
    staging = {
      replicas = 2
      debug    = true
    }
    production = {
      replicas = 5
      debug    = false
    }
  }
  
  current_config = lookup(local.workspace_config, terraform.workspace, local.workspace_config["default"])
}

resource "null_resource" "workspace_demo" {
  provisioner "local-exec" {
    command = "echo 'Workspace: ${terraform.workspace}, Replicas: ${local.current_config.replicas}'"
  }
}
```

---

## 11. Lifecycle Rules

Control resource behavior with lifecycle blocks:

```hcl
resource "null_resource" "lifecycle_demo" {
  triggers = {
    version = "1.0.0"
  }

  lifecycle {
    # Create new resource before destroying old one
    create_before_destroy = true
    
    # Prevent destruction
    # prevent_destroy = true
    
    # Ignore changes to specific attributes
    ignore_changes = [
      triggers["timestamp"],
    ]
  }

  provisioner "local-exec" {
    command = "echo 'Resource created'"
  }
}
```

---

## 12. Data Sources and External Data

The `external` data source runs a script and captures JSON output:

Create `scripts/get_info.sh`:

```bash
#!/bin/bash
# Must output valid JSON
cat << EOF
{
  "hostname": "$(hostname)",
  "date": "$(date -Iseconds)",
  "user": "${USER:-unknown}"
}
EOF
```

Make it executable and use it:

```bash
chmod +x scripts/get_info.sh
```

Add to your configuration:

```hcl
data "external" "system_info" {
  program = ["bash", "${path.module}/scripts/get_info.sh"]
}

resource "null_resource" "external_demo" {
  provisioner "local-exec" {
    command = "echo 'Running on ${data.external.system_info.result.hostname} as ${data.external.system_info.result.user}'"
  }
}

output "system_info" {
  value = data.external.system_info.result
}
```

---

## 13. Provisioner Behaviors

### on_failure handling

```hcl
resource "null_resource" "failure_handling" {
  provisioner "local-exec" {
    command    = "exit 1"  # This will fail
    on_failure = continue  # Options: fail (default) or continue
  }

  provisioner "local-exec" {
    command = "echo 'This still runs because of on_failure = continue'"
  }
}
```

### Environment variables

```hcl
resource "null_resource" "with_env" {
  provisioner "local-exec" {
    command = "echo \"App: $APP_NAME, Env: $DEPLOY_ENV\""
    
    environment = {
      APP_NAME   = var.app_name
      DEPLOY_ENV = var.environment
    }
  }
}
```

### Working directory

```hcl
resource "null_resource" "working_dir" {
  provisioner "local-exec" {
    command     = "pwd && ls -la"
    working_dir = "/tmp"
  }
}
```

### Different interpreters

```hcl
resource "null_resource" "python_script" {
  provisioner "local-exec" {
    command     = "print('Hello from Python')"
    interpreter = ["python3", "-c"]
  }
}
```

---

## 14. Validation and Formatting

### Variable validation

```hcl
variable "instance_type" {
  type        = string
  description = "Instance size"
  
  validation {
    condition     = contains(["small", "medium", "large"], var.instance_type)
    error_message = "Instance type must be small, medium, or large."
  }
}

variable "port" {
  type = number
  
  validation {
    condition     = var.port >= 1024 && var.port <= 65535
    error_message = "Port must be between 1024 and 65535."
  }
}
```

### Built-in commands

```bash
# Format all .tf files
terraform fmt

# Recursive formatting
terraform fmt -recursive

# Validate configuration
terraform validate

# Check formatting without changing files
terraform fmt -check
```

---

## 15. Debugging and Troubleshooting

### Enable detailed logging

```bash
# Set log level: TRACE, DEBUG, INFO, WARN, ERROR
export TF_LOG=DEBUG
terraform apply

# Log to file
export TF_LOG_PATH="terraform.log"

# Disable logging
unset TF_LOG
```

### Plan output

```bash
# Save plan to file
terraform plan -out=tfplan

# Show saved plan
terraform show tfplan

# Apply saved plan (no confirmation needed)
terraform apply tfplan

# Output plan as JSON for processing
terraform show -json tfplan > plan.json
```

---

## 16. Cleanup

Destroy all resources:

```bash
terraform destroy
```

Or target specific resources:

```bash
terraform destroy -target=null_resource.hello
```

---

## Quick Reference

| Command | Purpose |
|---------|---------|
| `terraform init` | Initialize working directory |
| `terraform plan` | Preview changes |
| `terraform apply` | Apply changes |
| `terraform destroy` | Destroy resources |
| `terraform fmt` | Format code |
| `terraform validate` | Validate configuration |
| `terraform state list` | List state resources |
| `terraform output` | Show outputs |
| `terraform workspace list` | List workspaces |
| `terraform graph` | Generate dependency graph |

---

## Next Steps

Once comfortable with these fundamentals, you're ready to:

1. Add cloud providers (AWS, GCP, Azure)
2. Set up remote state backends (S3, GCS, Terraform Cloud)
3. Implement CI/CD pipelines for Terraform
4. Explore Terragrunt for DRY configurations
5. Look into policy-as-code with Sentinel or OPA

Happy Terraforming!
