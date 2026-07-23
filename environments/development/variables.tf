variable "project_id" {
  type    = string
  default = "kt-tech-up-01"
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

variable "api_machine_type" {
  type    = string
  default = "e2-medium"
}

variable "langfuse_machine_type" {
  type    = string
  default = "e2-highmem-2"
}

variable "langfuse_image_tag" {
  type    = string
  default = "3.224.0"
}

variable "caddy_image_tag" {
  type    = string
  default = "2.11.4"
}

variable "github_organization" {
  type    = string
  default = "cosmos-incicrew"
}
