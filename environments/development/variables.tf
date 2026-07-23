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

variable "postgres_image" {
  type    = string
  default = "postgres:17@sha256:a426e44bac0b759c95894d68e1a0ac03ecc20b619f498a91aae373bf06d8508d"
}

variable "clickhouse_image" {
  type    = string
  default = "clickhouse/clickhouse-server:25.8.28.1@sha256:a9d328123ff8a61bf6b16448528b577d59deb85758172e13b09054b0727f8adf"
}

variable "redis_image" {
  type    = string
  default = "redis:7@sha256:a8f08480e1f88f2647fed492d1178c06abb0d0c1fbf02c682a61e2f483fb3954"
}

variable "minio_image" {
  type    = string
  default = "minio/minio:latest@sha256:14cea493d9a34af32f524e538b8346cf79f3321eff8e708c1e2960462bd8936e"
}

variable "github_organization" {
  type    = string
  default = "cosmos-incicrew"
}
