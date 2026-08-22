variable "yc_token" {
  description = "OAuth-токен или IAM-токен пользователя (только для первого запуска bootstrap). Передавайте через TF_VAR_yc_token, не храните в файле."
  type        = string
  sensitive   = true
}

variable "yc_cloud_id" {
  description = "ID облака в Яндекс.Облаке"
  type        = string
}

variable "yc_folder_id" {
  description = "ID каталога (folder), в котором создаётся инфраструктура"
  type        = string
}

variable "yc_zone" {
  description = "Зона доступности по умолчанию"
  type        = string
  default     = "ru-central1-a"
}

variable "service_account_name" {
  description = "Имя сервисного аккаунта для Terraform"
  type        = string
  default     = "terraform-sa"
}

variable "state_bucket_name" {
  description = "Имя S3-бакета для хранения terraform state (должно быть глобально уникальным)"
  type        = string
}
