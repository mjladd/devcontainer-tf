# lists_basics.tf

variable "server_names" {
  type    = list(string)
  default = ["web-server", "api-server", "db-server", "cache-server"]
}

# using count with lists
resource "null_resource" "servers_with_count" {
  count = length(var.server_names)

  provisioner "local-exec" {
    command = "echo 'processing server: ${var.server_names[count.index]} at index ${count.index}'"
  }
}

# using for_each with lists that are converted to sets
resource "null_resource" "servers_with_foreach" {
  for_each = toset(var.server_names)

  provisioner "local-exec" {
    command = "echo 'Processing server: ${each.value}'"
  }

}
