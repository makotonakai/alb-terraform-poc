variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "Primary region (e.g. asia-northeast1)"
}

variable "zones" {
  type        = list(string)
  description = "Zones used in the region"
}
