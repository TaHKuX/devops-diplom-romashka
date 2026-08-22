terraform {
  required_version = ">= 1.5.0"

  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = ">= 0.130.0"
    }
  }

  # Локальный state для bootstrap-конфигурации.
  # Она создаёт сам бакет для основной инфраструктуры, поэтому не может
  # использовать S3-backend сама на себя (курица и яйцо).
  # Файл terraform.tfstate храните бережно (не коммитьте!) или один раз
  # перенесите вручную в защищённое место после первого apply.
}

provider "yandex" {
  token     = var.yc_token
  cloud_id  = var.yc_cloud_id
  folder_id = var.yc_folder_id
  zone      = var.yc_zone
}
