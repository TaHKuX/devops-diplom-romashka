terraform {
  required_version = ">= 1.5.0"

  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = ">= 0.130.0"
    }
  }

  # Локальный state для bootstrap-конфигурации: она сама создает бакет,
  # поэтому не может использовать S3-backend на саму себя.
  # terraform.tfstate не коммитить.
}

provider "yandex" {
  token     = var.yc_token
  cloud_id  = var.yc_cloud_id
  folder_id = var.yc_folder_id
  zone      = var.yc_zone
}
