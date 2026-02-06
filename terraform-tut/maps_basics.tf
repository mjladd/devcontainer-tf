# maps basics

variable "server-configs" {
  type = map(object({
    instance_type = string,
    disk_size     = number,
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
      disk_size     = 400
      enabled       = false
    }
  }
}

resource "null_resource" "server_setup" {
  for_each = { for k, v in var.server-configs : k => v if v.enabled }

  provisioner "local-exec" {

    command = <<-EOT
      echo 'Setting up ${each.key}:'
    EOT
  }
}
