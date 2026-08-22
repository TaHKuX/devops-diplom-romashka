terraform {
  required_version = ">= 1.6.3" # skip_s3_checksum появился в 1.6.3, нужен для S3-совместимых сторов

  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = ">= 0.130.0"
    }
  }

  # bucket намеренно не задан здесь (partial configuration), передается через
  # -backend-config="bucket=<state_bucket_name>" при terraform init,
  # либо через backend.hcl (см. backend.hcl.example).
  backend "s3" {
    endpoint = "storage.yandexcloud.net"
    region   = "ru-central1"
    key      = "infra/terraform.tfstate"

    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_s3_checksum             = true
    skip_metadata_api_check      = true

    # access_key / secret_key передаются через переменные окружения
    # AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY (из output бутстрапа),
    # чтобы не хранить секреты в коде.
  }
}
