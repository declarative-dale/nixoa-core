variable "remote_host" {
  type        = string
  description = "IP address or FQDN of the XCP-ng pool master."
  sensitive   = true
}

variable "remote_username" {
  type        = string
  description = "XCP-ng API username."
  sensitive   = true
  default     = "root"
}

variable "remote_password" {
  type        = string
  description = "XCP-ng API password. Supply with PKR_VAR_remote_password."
  sensitive   = true
}

variable "sr_iso_name" {
  type        = string
  description = "ISO storage repository used for the NiXOA installer."
}

variable "sr_name" {
  type        = string
  description = "Storage repository used for the template disk."
}

variable "iso_url" {
  type        = string
  description = "Absolute path to the generated NiXOA installer ISO."
}

variable "iso_checksum" {
  type        = string
  description = "Installer checksum in sha256:<hex> form."
}

variable "operator_public_key_file" {
  type        = string
  description = "Local SSH public key installed for the nixoa operator."
}

variable "repo_url" {
  type        = string
  description = "Core repository cloned by the installer."
  default     = "https://github.com/closure-labs/nixoa.git"
}

variable "repo_branch" {
  type        = string
  description = "Core repository branch installed into the template."
  default     = "main"
}

variable "clone_template" {
  type        = string
  description = "XCP-ng template cloned to create the installer VM."
  default     = "Other install media"
}

variable "network_names" {
  type        = list(string)
  description = "Networks attached to the installer VM; the first must provide DHCP."

  validation {
    condition     = length(var.network_names) > 0
    error_message = "Network names must contain at least one DHCP-enabled network."
  }
}

variable "export_network_names" {
  type        = list(string)
  description = "Networks retained on the finished native template."

  validation {
    condition     = length(var.export_network_names) > 0
    error_message = "Export network names must contain at least one network."
  }
}

variable "vm_name" {
  type        = string
  description = "Native XCP-ng template name."
  default     = null
}

variable "vm_description" {
  type        = string
  description = "Native XCP-ng template description."
  default     = null
}

variable "vm_tags" {
  type        = list(string)
  description = "Tags applied to the native template."
  default = [
    "nixoa",
    "nixos",
    "packer",
    "template",
    "cloud-init",
  ]
}

variable "vcpus" {
  type        = number
  description = "Maximum and startup virtual CPU count."
  default     = 2

  validation {
    condition     = var.vcpus >= 2
    error_message = "The virtual CPU count must be at least 2."
  }
}

variable "memory_mb" {
  type        = number
  description = "VM memory in MiB."
  default     = 4096

  validation {
    condition     = var.memory_mb >= 4096
    error_message = "The memory allocation must be at least 4096 MiB."
  }
}

variable "disk_size_mb" {
  type        = number
  description = "Template disk size in MiB."
  default     = 20480

  validation {
    condition     = var.disk_size_mb >= 20480
    error_message = "The disk size must be at least 20480 MiB."
  }
}

variable "install_timeout" {
  type        = string
  description = "Maximum time for installation and initial guest discovery."
  default     = "120m"
}

variable "ssh_wait_timeout" {
  type        = string
  description = "Maximum time for SSH after installation or reboot."
  default     = "120m"
}

variable "ssh_handshake_attempts" {
  type        = number
  description = "Maximum SSH handshake attempts during installation."
  default     = 10000
}
