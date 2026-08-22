variable "yc_token" {
  description = "OAuth/IAM токен или ключ сервисного аккаунта terraform-sa"
  type        = string
  sensitive   = true
}

variable "yc_cloud_id" {
  type = string
}

variable "yc_folder_id" {
  type = string
}

variable "yc_zone" {
  type    = string
  default = "ru-central1-a"
}

variable "prefix" {
  description = "Префикс для имен ресурсов"
  type        = string
  default     = "rtankih"
}

variable "zones" {
  description = "Зоны доступности для подсетей и нод кластера"
  type        = list(string)
  default     = ["ru-central1-a", "ru-central1-b", "ru-central1-d"]
}

variable "node_resources" {
  description = "Ресурсы для worker-нод (минимально достаточные, экономим бюджет)"
  type = object({
    cores         = number
    memory        = number
    core_fraction = number
  })
  default = {
    cores         = 2
    memory        = 2
    core_fraction = 20
  }
}

variable "node_count_per_zone" {
  description = "Количество нод на зону в node group (fixed scale)"
  type        = number
  default     = 1
}
