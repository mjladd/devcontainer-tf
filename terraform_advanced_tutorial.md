# Advanced Terraform Tutorial: Maps, Lists, and Complex Data Structures

This tutorial covers advanced Terraform concepts using `null_resource` so you can practice without creating actual infrastructure. Perfect for learning complex patterns safely!

## Table of Contents
1. [Setup](#setup)
2. [Working with Lists](#working-with-lists)
3. [Working with Maps](#working-with-maps)
4. [Complex Data Structures](#complex-data-structures)
5. [Dynamic Blocks](#dynamic-blocks)
6. [For Expressions](#for-expressions)
7. [Conditional Expressions](#conditional-expressions)
8. [Local Values and Data Processing](#local-values-and-data-processing)
9. [Count vs For_Each](#count-vs-for_each)
10. [Advanced Functions](#advanced-functions)

---

## Setup

Create a new directory and initialize it:

```bash
mkdir terraform-advanced-tutorial
cd terraform-advanced-tutorial
terraform init
```

---

## 1. Working with Lists

### Example 1.1: Basic List Iteration

```hcl
# lists_basic.tf

variable "server_names" {
  type    = list(string)
  default = ["web-server", "api-server", "db-server", "cache-server"]
}

# Using count with lists
resource "null_resource" "servers_with_count" {
  count = length(var.server_names)

  provisioner "local-exec" {
    command = "echo 'Processing server: ${var.server_names[count.index]} at index ${count.index}'"
  }
}

# Using for_each with lists (converted to set)
resource "null_resource" "servers_with_foreach" {
  for_each = toset(var.server_names)

  provisioner "local-exec" {
    command = "echo 'Processing server: ${each.value}'"
  }
}

output "server_count" {
  value = "Total servers: ${length(var.server_names)}"
}
```

### Example 1.2: List Manipulation

```hcl
# lists_advanced.tf

variable "environments" {
  type    = list(string)
  default = ["dev", "staging", "prod"]
}

variable "regions" {
  type    = list(string)
  default = ["us-east-1", "us-west-2", "eu-west-1"]
}

locals {
  # Create combinations of environments and regions
  env_region_combinations = flatten([
    for env in var.environments : [
      for region in var.regions : {
        environment = env
        region      = region
        name        = "${env}-${region}"
      }
    ]
  ])
}

resource "null_resource" "deployment_combinations" {
  for_each = { for combo in local.env_region_combinations : combo.name => combo }

  provisioner "local-exec" {
    command = "echo 'Deployment: ${each.value.name} (${each.value.environment} in ${each.value.region})'"
  }
}

output "all_combinations" {
  value = [for combo in local.env_region_combinations : combo.name]
}
```

---

## 2. Working with Maps

### Example 2.1: Basic Maps

```hcl
# maps_basic.tf

variable "server_configs" {
  type = map(object({
    instance_type = string
    disk_size     = number
    enabled       = bool
  }))
  default = {
    web = {
      instance_type = "t3.medium"
      disk_size     = 50
      enabled       = true
    }
    api = {
      instance_type = "t3.large"
      disk_size     = 100
      enabled       = true
    }
    worker = {
      instance_type = "t3.xlarge"
      disk_size     = 200
      enabled       = false
    }
  }
}

resource "null_resource" "server_setup" {
  for_each = { for k, v in var.server_configs : k => v if v.enabled }

  provisioner "local-exec" {
    command = <<-EOT
      echo 'Setting up ${each.key}:'
      echo '  Type: ${each.value.instance_type}'
      echo '  Disk: ${each.value.disk_size}GB'
    EOT
  }
}

output "enabled_servers" {
  value = { for k, v in var.server_configs : k => v.instance_type if v.enabled }
}
```

### Example 2.2: Nested Maps

```hcl
# maps_nested.tf

variable "infrastructure" {
  type = map(map(object({
    cidr_block = string
    tags       = map(string)
  })))
  default = {
    production = {
      vpc = {
        cidr_block = "10.0.0.0/16"
        tags = {
          Environment = "prod"
          CostCenter  = "engineering"
        }
      }
      subnet_public = {
        cidr_block = "10.0.1.0/24"
        tags = {
          Type = "public"
          Tier = "web"
        }
      }
    }
    development = {
      vpc = {
        cidr_block = "10.1.0.0/16"
        tags = {
          Environment = "dev"
          CostCenter  = "engineering"
        }
      }
      subnet_public = {
        cidr_block = "10.1.1.0/24"
        tags = {
          Type = "public"
          Tier = "web"
        }
      }
    }
  }
}

locals {
  # Flatten nested structure
  all_resources = flatten([
    for env_name, env_config in var.infrastructure : [
      for resource_name, resource_config in env_config : {
        id         = "${env_name}-${resource_name}"
        env        = env_name
        resource   = resource_name
        cidr_block = resource_config.cidr_block
        tags       = resource_config.tags
      }
    ]
  ])
}

resource "null_resource" "network_resources" {
  for_each = { for r in local.all_resources : r.id => r }

  provisioner "local-exec" {
    command = "echo 'Resource: ${each.key} | CIDR: ${each.value.cidr_block} | Env: ${each.value.env}'"
  }
}
```

---

## 3. Complex Data Structures

### Example 3.1: Mixed Data Types

```hcl
# complex_structures.tf

variable "application_stack" {
  type = object({
    name    = string
    version = string
    services = list(object({
      name          = string
      replicas      = number
      ports         = list(number)
      environment   = map(string)
      health_check  = object({
        enabled  = bool
        path     = string
        interval = number
      })
    }))
    global_tags = map(string)
  })
  
  default = {
    name    = "my-app"
    version = "1.0.0"
    services = [
      {
        name     = "frontend"
        replicas = 3
        ports    = [80, 443]
        environment = {
          NODE_ENV = "production"
          API_URL  = "http://api:8080"
        }
        health_check = {
          enabled  = true
          path     = "/health"
          interval = 30
        }
      },
      {
        name     = "backend"
        replicas = 5
        ports    = [8080]
        environment = {
          DB_HOST = "postgres:5432"
          CACHE   = "redis:6379"
        }
        health_check = {
          enabled  = true
          path     = "/api/health"
          interval = 15
        }
      }
    ]
    global_tags = {
      Project     = "WebApp"
      ManagedBy   = "Terraform"
      Environment = "production"
    }
  }
}

locals {
  # Extract all ports from all services
  all_ports = distinct(flatten([
    for service in var.application_stack.services : service.ports
  ]))
  
  # Create service configurations
  service_configs = {
    for service in var.application_stack.services :
    service.name => merge(
      {
        replicas    = service.replicas
        ports       = service.ports
        environment = service.environment
      },
      var.application_stack.global_tags
    )
  }
}

resource "null_resource" "deploy_services" {
  for_each = local.service_configs

  provisioner "local-exec" {
    command = <<-EOT
      echo '=== Deploying ${each.key} ==='
      echo 'Replicas: ${each.value.replicas}'
      echo 'Ports: ${jsonencode(each.value.ports)}'
      echo 'Environment: ${jsonencode(each.value.environment)}'
    EOT
  }

  triggers = {
    config_hash = md5(jsonencode(each.value))
  }
}

output "deployment_summary" {
  value = {
    application = var.application_stack.name
    version     = var.application_stack.version
    services    = [for s in var.application_stack.services : s.name]
    total_ports = local.all_ports
  }
}
```

---

## 4. Dynamic Blocks

### Example 4.1: Dynamic Ingress Rules

```hcl
# dynamic_blocks.tf

variable "security_rules" {
  type = list(object({
    description = string
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
  }))
  default = [
    {
      description = "HTTP"
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    },
    {
      description = "HTTPS"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    },
    {
      description = "SSH"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["10.0.0.0/8"]
    }
  ]
}

locals {
  # Simulate security group with dynamic blocks
  security_config = {
    name        = "web-sg"
    description = "Security group for web servers"
    ingress_rules = [
      for rule in var.security_rules : {
        description = rule.description
        from_port   = rule.from_port
        to_port     = rule.to_port
        protocol    = rule.protocol
        cidr_blocks = rule.cidr_blocks
      }
    ]
  }
}

resource "null_resource" "security_group_simulation" {
  count = length(local.security_config.ingress_rules)

  provisioner "local-exec" {
    command = <<-EOT
      echo 'Rule ${count.index + 1}: ${local.security_config.ingress_rules[count.index].description}'
      echo '  Port: ${local.security_config.ingress_rules[count.index].from_port}-${local.security_config.ingress_rules[count.index].to_port}'
      echo '  Protocol: ${local.security_config.ingress_rules[count.index].protocol}'
      echo '  CIDR: ${jsonencode(local.security_config.ingress_rules[count.index].cidr_blocks)}'
    EOT
  }
}
```

---

## 5. For Expressions

### Example 5.1: List and Map Transformations

```hcl
# for_expressions.tf

variable "users" {
  type = list(object({
    username = string
    email    = string
    role     = string
    active   = bool
  }))
  default = [
    { username = "alice", email = "alice@example.com", role = "admin", active = true },
    { username = "bob", email = "bob@example.com", role = "developer", active = true },
    { username = "charlie", email = "charlie@example.com", role = "developer", active = false },
    { username = "diana", email = "diana@example.com", role = "analyst", active = true },
  ]
}

locals {
  # List transformations
  active_users = [for u in var.users : u.username if u.active]
  user_emails  = [for u in var.users : u.email]
  
  # Map transformations
  users_by_name = { for u in var.users : u.username => u }
  users_by_role = { for u in var.users : u.username => u.role }
  
  # Grouped by role
  users_by_role_grouped = {
    for role in distinct([for u in var.users : u.role]) :
    role => [for u in var.users : u.username if u.role == role]
  }
  
  # Complex transformation
  user_access_map = {
    for u in var.users :
    u.username => {
      email      = upper(u.email)
      can_access = u.active
      permissions = u.role == "admin" ? ["read", "write", "delete"] : ["read"]
    }
  }
}

resource "null_resource" "user_provisioning" {
  for_each = { for u in var.users : u.username => u if u.active }

  provisioner "local-exec" {
    command = "echo 'Provisioning user: ${each.key} (${each.value.role})'"
  }
}

output "user_summary" {
  value = {
    total_users      = length(var.users)
    active_users     = local.active_users
    users_by_role    = local.users_by_role_grouped
    admin_count      = length([for u in var.users : u if u.role == "admin"])
  }
}
```

### Example 5.2: Advanced Filtering and Mapping

```hcl
# for_advanced.tf

variable "resources" {
  type = list(object({
    name        = string
    type        = string
    size        = string
    cost_per_hour = number
    tags        = map(string)
  }))
  default = [
    {
      name = "web-1"
      type = "compute"
      size = "large"
      cost_per_hour = 0.50
      tags = { env = "prod", team = "frontend" }
    },
    {
      name = "web-2"
      type = "compute"
      size = "medium"
      cost_per_hour = 0.25
      tags = { env = "prod", team = "frontend" }
    },
    {
      name = "db-1"
      type = "database"
      size = "xlarge"
      cost_per_hour = 1.50
      tags = { env = "prod", team = "backend" }
    },
    {
      name = "cache-1"
      type = "cache"
      size = "small"
      cost_per_hour = 0.10
      tags = { env = "dev", team = "backend" }
    }
  ]
}

locals {
  # Production resources only
  prod_resources = [for r in var.resources : r if lookup(r.tags, "env", "") == "prod"]
  
  # Calculate monthly costs
  monthly_costs = {
    for r in var.resources :
    r.name => r.cost_per_hour * 24 * 30
  }
  
  # Group by team and calculate team costs
  team_costs = {
    for team in distinct([for r in var.resources : lookup(r.tags, "team", "unknown")]) :
    team => sum([
      for r in var.resources :
      r.cost_per_hour * 24 * 30
      if lookup(r.tags, "team", "") == team
    ])
  }
  
  # Create resource map with calculated values
  resource_analysis = {
    for r in var.resources :
    r.name => {
      type           = r.type
      size           = r.size
      hourly_cost    = r.cost_per_hour
      monthly_cost   = r.cost_per_hour * 24 * 30
      is_production  = lookup(r.tags, "env", "") == "prod"
      team           = lookup(r.tags, "team", "unknown")
    }
  }
}

resource "null_resource" "resource_analysis" {
  for_each = local.resource_analysis

  provisioner "local-exec" {
    command = <<-EOT
      echo 'Resource: ${each.key}'
      echo '  Type: ${each.value.type} (${each.value.size})'
      echo '  Monthly Cost: $${each.value.monthly_cost}'
      echo '  Production: ${each.value.is_production}'
    EOT
  }
}

output "cost_analysis" {
  value = {
    total_monthly_cost = sum(values(local.monthly_costs))
    team_costs         = local.team_costs
    prod_resource_count = length(local.prod_resources)
  }
}
```

---

## 6. Conditional Expressions

### Example 6.1: Ternary Operations

```hcl
# conditionals.tf

variable "environment" {
  type    = string
  default = "production"
}

variable "enable_monitoring" {
  type    = bool
  default = true
}

variable "instance_count" {
  type    = number
  default = 3
}

locals {
  # Simple conditionals
  is_production = var.environment == "production"
  instance_size = var.environment == "production" ? "large" : "small"
  
  # Nested conditionals
  backup_retention = (
    var.environment == "production" ? 30 :
    var.environment == "staging" ? 7 :
    1
  )
  
  # Conditional with boolean
  monitoring_config = var.enable_monitoring ? {
    enabled      = true
    interval     = 60
    notification = "email"
  } : {
    enabled = false
  }
  
  # Conditional list
  required_tags = concat(
    ["Name", "Environment"],
    var.environment == "production" ? ["CostCenter", "Owner"] : []
  )
  
  # Conditional resource count
  actual_instance_count = var.environment == "production" ? var.instance_count : 1
}

resource "null_resource" "conditional_deployment" {
  count = local.is_production ? 3 : 1

  provisioner "local-exec" {
    command = "echo 'Deploying instance ${count.index + 1} with size: ${local.instance_size}'"
  }
}

resource "null_resource" "monitoring" {
  count = var.enable_monitoring ? 1 : 0

  provisioner "local-exec" {
    command = "echo 'Setting up monitoring with ${local.monitoring_config.interval}s interval'"
  }
}

output "deployment_config" {
  value = {
    environment       = var.environment
    is_production     = local.is_production
    instance_size     = local.instance_size
    instance_count    = local.actual_instance_count
    backup_retention  = local.backup_retention
    monitoring        = local.monitoring_config
    required_tags     = local.required_tags
  }
}
```

---

## 7. Local Values and Data Processing

### Example 7.1: Complex Data Processing

```hcl
# locals_processing.tf

variable "raw_data" {
  type = list(object({
    timestamp = string
    metric    = string
    value     = number
    source    = string
  }))
  default = [
    { timestamp = "2024-01-01T10:00:00Z", metric = "cpu", value = 45.5, source = "server-1" },
    { timestamp = "2024-01-01T10:01:00Z", metric = "cpu", value = 52.3, source = "server-1" },
    { timestamp = "2024-01-01T10:00:00Z", metric = "memory", value = 68.2, source = "server-1" },
    { timestamp = "2024-01-01T10:00:00Z", metric = "cpu", value = 38.7, source = "server-2" },
    { timestamp = "2024-01-01T10:01:00Z", metric = "cpu", value = 41.2, source = "server-2" },
  ]
}

locals {
  # Group by metric
  metrics_by_type = {
    for metric_type in distinct([for d in var.raw_data : d.metric]) :
    metric_type => [for d in var.raw_data : d if d.metric == metric_type]
  }
  
  # Calculate averages by metric and source
  metric_averages = {
    for metric_type in distinct([for d in var.raw_data : d.metric]) :
    metric_type => {
      for source in distinct([for d in var.raw_data : d.source if d.metric == metric_type]) :
      source => sum([
        for d in var.raw_data :
        d.value if d.metric == metric_type && d.source == source
      ]) / length([
        for d in var.raw_data :
        d if d.metric == metric_type && d.source == source
      ])
    }
  }
  
  # Identify high values (> 50)
  high_value_alerts = [
    for d in var.raw_data :
    {
      alert_id = "${d.source}-${d.metric}-${d.timestamp}"
      message  = "${d.metric} on ${d.source} is high: ${d.value}"
      severity = d.value > 70 ? "critical" : "warning"
    }
    if d.value > 50
  ]
  
  # Create summary statistics
  summary_stats = {
    total_readings = length(var.raw_data)
    unique_sources = distinct([for d in var.raw_data : d.source])
    unique_metrics = distinct([for d in var.raw_data : d.metric])
    max_value = max([for d in var.raw_data : d.value]...)
    min_value = min([for d in var.raw_data : d.value]...)
    avg_value = sum([for d in var.raw_data : d.value]...) / length(var.raw_data)
  }
}

resource "null_resource" "process_metrics" {
  for_each = local.metrics_by_type

  provisioner "local-exec" {
    command = "echo 'Processing ${each.key}: ${length(each.value)} readings'"
  }
}

resource "null_resource" "high_value_alerts" {
  for_each = { for alert in local.high_value_alerts : alert.alert_id => alert }

  provisioner "local-exec" {
    command = "echo '[${upper(each.value.severity)}] ${each.value.message}'"
  }
}

output "analytics_summary" {
  value = {
    statistics = local.summary_stats
    averages   = local.metric_averages
    alerts     = length(local.high_value_alerts)
  }
}
```

---

## 8. Count vs For_Each

### Example 8.1: Demonstrating the Differences

```hcl
# count_vs_foreach.tf

variable "items_list" {
  type    = list(string)
  default = ["item-a", "item-b", "item-c", "item-d"]
}

variable "items_map" {
  type = map(object({
    priority = number
    enabled  = bool
  }))
  default = {
    service-1 = { priority = 1, enabled = true }
    service-2 = { priority = 2, enabled = true }
    service-3 = { priority = 3, enabled = false }
    service-4 = { priority = 1, enabled = true }
  }
}

# Using COUNT (index-based)
resource "null_resource" "with_count" {
  count = length(var.items_list)

  provisioner "local-exec" {
    command = "echo 'COUNT - Index: ${count.index}, Value: ${var.items_list[count.index]}'"
  }

  # Demonstrates count issue: if you remove item-b from the list,
  # item-c moves from index 2 to index 1, triggering unnecessary recreation
}

# Using FOR_EACH with list (converted to set)
resource "null_resource" "with_foreach_list" {
  for_each = toset(var.items_list)

  provisioner "local-exec" {
    command = "echo 'FOR_EACH (list) - Key: ${each.key}, Value: ${each.value}'"
  }

  # With for_each, removing item-b only affects that specific resource
  # Other resources remain unchanged
}

# Using FOR_EACH with map
resource "null_resource" "with_foreach_map" {
  for_each = { for k, v in var.items_map : k => v if v.enabled }

  provisioner "local-exec" {
    command = "echo 'FOR_EACH (map) - Key: ${each.key}, Priority: ${each.value.priority}'"
  }

  # Map keys are stable identifiers, making this the most predictable approach
}

# Advanced: Creating a map from list for stable keys
locals {
  items_as_map = { for idx, item in var.items_list : item => idx }
}

resource "null_resource" "list_to_map" {
  for_each = local.items_as_map

  provisioner "local-exec" {
    command = "echo 'LIST->MAP - Key: ${each.key}, Original Index: ${each.value}'"
  }
}

output "comparison" {
  value = {
    count_length         = length(var.items_list)
    foreach_list_keys    = keys(null_resource.with_foreach_list)
    foreach_map_keys     = keys(null_resource.with_foreach_map)
    enabled_services     = [for k, v in var.items_map : k if v.enabled]
  }
}
```

---

## 9. Advanced Functions

### Example 9.1: String and Collection Functions

```hcl
# functions_advanced.tf

variable "config_string" {
  type    = string
  default = "app=myapp,env=production,version=1.2.3,team=platform"
}

variable "ip_addresses" {
  type    = list(string)
  default = ["10.0.1.5", "10.0.1.10", "10.0.2.15", "10.0.3.20"]
}

locals {
  # String manipulation
  config_pairs = split(",", var.config_string)
  config_map = {
    for pair in local.config_pairs :
    split("=", pair)[0] => split("=", pair)[1]
  }
  
  # JSON encoding/decoding
  config_json = jsonencode(local.config_map)
  
  # Template rendering
  greeting_template = "Hello, ${local.config_map["team"]} team! Running ${local.config_map["app"]} v${local.config_map["version"]}"
  
  # CIDR calculations
  ip_subnets = [for ip in var.ip_addresses : cidrsubnet("10.0.0.0/16", 8, index(var.ip_addresses, ip))]
  
  # Merge operations
  default_tags = {
    ManagedBy = "Terraform"
    Project   = "Tutorial"
  }
  
  merged_tags = merge(
    local.default_tags,
    local.config_map,
    { Timestamp = timestamp() }
  )
  
  # Collection operations
  sorted_ips = sort(var.ip_addresses)
  unique_octets = distinct(flatten([
    for ip in var.ip_addresses :
    split(".", ip)
  ]))
  
  # Regex operations
  version_parts = regex("^([0-9]+)\\.([0-9]+)\\.([0-9]+)$", local.config_map["version"])
  major_version = local.version_parts[0]
  minor_version = local.version_parts[1]
  patch_version = local.version_parts[2]
  
  # File hash (for change detection)
  config_hash = md5(jsonencode(local.config_map))
  
  # Lookup with default
  environment_config = {
    production = { replicas = 5, size = "large" }
    staging    = { replicas = 2, size = "medium" }
    dev        = { replicas = 1, size = "small" }
  }
  
  current_env_config = lookup(
    local.environment_config,
    local.config_map["env"],
    { replicas = 1, size = "small" }
  )
}

resource "null_resource" "function_demo" {
  provisioner "local-exec" {
    command = <<-EOT
      echo '=== Configuration ==='
      echo 'Raw: ${var.config_string}'
      echo 'Parsed: ${jsonencode(local.config_map)}'
      echo 'Hash: ${local.config_hash}'
      echo ''
      echo '=== Version Info ==='
      echo 'Major: ${local.major_version}'
      echo 'Minor: ${local.minor_version}'
      echo 'Patch: ${local.patch_version}'
      echo ''
      echo '=== Environment ==='
      echo 'Replicas: ${local.current_env_config.replicas}'
      echo 'Size: ${local.current_env_config.size}'
    EOT
  }

  triggers = {
    config_hash = local.config_hash
  }
}

output "function_results" {
  value = {
    config_map        = local.config_map
    version_info = {
      major = local.major_version
      minor = local.minor_version
      patch = local.patch_version
    }
    merged_tags       = local.merged_tags
    sorted_ips        = local.sorted_ips
    env_config        = local.current_env_config
  }
}
```

### Example 9.2: Type Conversion and Validation

```hcl
# type_conversion.tf

variable "mixed_inputs" {
  type = object({
    string_number = string
    list_of_nums  = list(string)
    bool_string   = string
    json_string   = string
  })
  default = {
    string_number = "42"
    list_of_nums  = ["1", "2", "3", "4", "5"]
    bool_string   = "true"
    json_string   = "{\"name\":\"test\",\"value\":123}"
  }
}

locals {
  # Type conversions
  converted_number = tonumber(var.mixed_inputs.string_number)
  converted_list   = [for s in var.mixed_inputs.list_of_nums : tonumber(s)]
  converted_bool   = tobool(var.mixed_inputs.bool_string)
  parsed_json      = jsondecode(var.mixed_inputs.json_string)
  
  # Calculations with converted types
  sum_of_list  = sum(local.converted_list)
  avg_of_list  = local.sum_of_list / length(local.converted_list)
  max_in_list  = max(local.converted_list...)
  min_in_list  = min(local.converted_list...)
  
  # Conditional based on converted bool
  deployment_mode = local.converted_bool ? "enabled" : "disabled"
  
  # Complex object construction
  processed_data = {
    original_input  = var.mixed_inputs.string_number
    as_number       = local.converted_number
    doubled         = local.converted_number * 2
    is_even         = local.converted_number % 2 == 0
    list_stats = {
      values  = local.converted_list
      sum     = local.sum_of_list
      average = local.avg_of_list
      max     = local.max_in_list
      min     = local.min_in_list
    }
    json_data = local.parsed_json
  }
  
  # Try function for safe operations
  safe_conversion = try(tonumber("not_a_number"), 0)
  safe_lookup     = try(local.parsed_json.nonexistent_key, "default_value")
}

resource "null_resource" "type_demo" {
  provisioner "local-exec" {
    command = <<-EOT
      echo 'Original: "${var.mixed_inputs.string_number}" (string)'
      echo 'Converted: ${local.converted_number} (number)'
      echo 'Doubled: ${local.converted_number * 2}'
      echo 'Is Even: ${local.processed_data.is_even}'
      echo 'List Sum: ${local.sum_of_list}'
      echo 'List Avg: ${local.avg_of_list}'
      echo 'Deployment: ${local.deployment_mode}'
    EOT
  }
}

output "type_conversion_results" {
  value = local.processed_data
}
```

---

## 10. Putting It All Together: Real-World Example

### Example 10.1: Multi-Tier Application Deployment

```hcl
# complete_example.tf

variable "application" {
  type = object({
    name        = string
    environment = string
    regions     = list(string)
    tiers = map(object({
      instance_type  = string
      min_instances  = number
      max_instances  = number
      health_check   = string
      dependencies   = list(string)
    }))
    feature_flags = map(bool)
  })
  
  default = {
    name        = "ecommerce-platform"
    environment = "production"
    regions     = ["us-east-1", "us-west-2", "eu-west-1"]
    tiers = {
      web = {
        instance_type  = "t3.medium"
        min_instances  = 2
        max_instances  = 10
        health_check   = "/health"
        dependencies   = ["api"]
      }
      api = {
        instance_type  = "t3.large"
        min_instances  = 3
        max_instances  = 15
        health_check   = "/api/health"
        dependencies   = ["database", "cache"]
      }
      database = {
        instance_type  = "r5.xlarge"
        min_instances  = 2
        max_instances  = 2
        health_check   = "/db/ping"
        dependencies   = []
      }
      cache = {
        instance_type  = "r5.large"
        min_instances  = 2
        max_instances  = 5
        health_check   = "/cache/ping"
        dependencies   = []
      }
    }
    feature_flags = {
      enable_cdn          = true
      enable_waf          = true
      enable_auto_scaling = true
      enable_monitoring   = true
    }
  }
}

locals {
  # Generate deployment matrix
  deployments = flatten([
    for region in var.application.regions : [
      for tier_name, tier_config in var.application.tiers : {
        id               = "${var.application.name}-${tier_name}-${region}"
        region           = region
        tier             = tier_name
        instance_type    = tier_config.instance_type
        min_instances    = tier_config.min_instances
        max_instances    = tier_config.max_instances
        health_check     = tier_config.health_check
        dependencies     = tier_config.dependencies
        auto_scaling     = var.application.feature_flags.enable_auto_scaling
      }
    ]
  ])
  
  # Calculate total instances
  total_min_instances = sum([
    for d in local.deployments : d.min_instances
  ])
  
  total_max_instances = sum([
    for d in local.deployments : d.max_instances
  ])
  
  # Group by tier for analysis
  instances_by_tier = {
    for tier in distinct([for d in local.deployments : d.tier]) :
    tier => {
      total_deployments = length([for d in local.deployments : d if d.tier == tier])
      min_instances     = sum([for d in local.deployments : d.min_instances if d.tier == tier])
      max_instances     = sum([for d in local.deployments : d.max_instances if d.tier == tier])
      regions           = [for d in local.deployments : d.region if d.tier == tier]
    }
  }
  
  # Calculate deployment order based on dependencies
  deployment_order = {
    phase1 = [for d in local.deployments : d.id if length(d.dependencies) == 0]
    phase2 = [for d in local.deployments : d.id if length(d.dependencies) > 0]
  }
  
  # Create configuration hash for each deployment
  deployment_configs = {
    for d in local.deployments :
    d.id => {
      config_hash = md5(jsonencode(d))
      tier        = d.tier
      region      = d.region
      settings    = {
        instance_type = d.instance_type
        scaling = d.auto_scaling ? {
          min = d.min_instances
          max = d.max_instances
        } : null
        health_check = d.health_check
      }
    }
  }
}

# Deploy infrastructure resources
resource "null_resource" "deploy_infrastructure" {
  for_each = { for d in local.deployments : d.id => d }

  provisioner "local-exec" {
    command = <<-EOT
      echo '==================================='
      echo 'Deploying: ${each.key}'
      echo 'Region: ${each.value.region}'
      echo 'Tier: ${each.value.tier}'
      echo 'Instance Type: ${each.value.instance_type}'
      echo 'Instances: ${each.value.min_instances}-${each.value.max_instances}'
      echo 'Dependencies: ${jsonencode(each.value.dependencies)}'
      echo 'Auto-scaling: ${each.value.auto_scaling}'
      echo '==================================='
    EOT
  }

  triggers = {
    config_hash = local.deployment_configs[each.key].config_hash
  }
}

# Optional monitoring based on feature flag
resource "null_resource" "setup_monitoring" {
  count = var.application.feature_flags.enable_monitoring ? 1 : 0

  provisioner "local-exec" {
    command = "echo 'Setting up monitoring for ${var.application.name} in ${var.application.environment}'"
  }

  depends_on = [null_resource.deploy_infrastructure]
}

# Optional CDN configuration
resource "null_resource" "configure_cdn" {
  count = var.application.feature_flags.enable_cdn ? 1 : 0

  provisioner "local-exec" {
    command = "echo 'Configuring CDN for web tier across ${length(var.application.regions)} regions'"
  }

  depends_on = [null_resource.deploy_infrastructure]
}

# Outputs
output "deployment_summary" {
  value = {
    application         = var.application.name
    environment         = var.application.environment
    total_deployments   = length(local.deployments)
    total_min_instances = local.total_min_instances
    total_max_instances = local.total_max_instances
    instances_by_tier   = local.instances_by_tier
    deployment_phases   = local.deployment_order
    enabled_features = [
      for feature, enabled in var.application.feature_flags :
      feature if enabled
    ]
  }
}

output "deployment_matrix" {
  value = {
    for region in var.application.regions :
    region => {
      for tier_name, tier_config in var.application.tiers :
      tier_name => {
        instances = "${tier_config.min_instances}-${tier_config.max_instances}"
        type      = tier_config.instance_type
      }
    }
  }
}
```

---

## Running the Examples

To test these examples:

1. Create individual `.tf` files or combine them in one directory
2. Initialize Terraform:
   ```bash
   terraform init
   ```

3. Validate the configuration:
   ```bash
   terraform validate
   ```

4. See the planned changes:
   ```bash
   terraform plan
   ```

5. Apply the configuration:
   ```bash
   terraform apply
   ```

6. View outputs:
   ```bash
   terraform output
   ```

7. Clean up:
   ```bash
   terraform destroy
   ```

## Key Takeaways

1. **Lists vs Maps**: Use maps for stable resource identifiers, lists for ordered collections
2. **for_each vs count**: Prefer `for_each` for most use cases to avoid resource recreation issues
3. **For expressions**: Powerful for transforming and filtering data structures
4. **Local values**: Essential for complex data processing and avoiding repetition
5. **Conditionals**: Use ternary operators and count/for_each combinations for flexible configurations
6. **Type conversions**: Always validate and convert types explicitly
7. **null_resource**: Perfect for learning and testing Terraform logic without infrastructure costs

## Practice Exercises

1. Create a multi-environment configuration using maps and conditional logic
2. Build a resource matrix combining regions, environments, and tiers
3. Implement a configuration validation system using local values
4. Create a cost calculator using for expressions and functions
5. Design a blue-green deployment configuration using conditional expressions

Happy learning! 🚀
