variable "resource_prefix" {
  type        = "string"
  default     = "terraform"
  description = "Service prefix to use for naming of resources."
}

# Define Azure region for resource placement.
variable "location" {
  type        = "string"
  default     = "westus"
  description = "Azure region for deployment of resources."
}

# Define username for use on the hosts.
variable "username" {
  type        = "string"
  default     = "piyush"
  description = "Username to build and use on the VM hosts."
}