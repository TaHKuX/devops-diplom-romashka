# Сервисный аккаунт, которым в дальнейшем будет пользоваться Terraform
# для создания основной инфраструктуры. Права выданы точечно, без editor/admin
# на весь каталог.
resource "yandex_iam_service_account" "terraform" {
  name        = var.service_account_name
  description = "Service account used by Terraform to manage infra"
  folder_id   = var.yc_folder_id
}

locals {
  # Минимально необходимый набор ролей для задач диплома:
  # сеть, вычислительные ресурсы, managed k8s, container registry, object storage.
  sa_roles = [
    "vpc.admin",
    "compute.admin",
    "k8s.admin",
    "container-registry.admin",
    "storage.admin",
    "iam.serviceAccounts.user",
    # Нужна, чтобы terraform-sa мог сам выдавать роли другим сервисным
    # аккаунтам (k8s.clusters.agent и т.д.) на этом folder. Область
    # действия - только этот folder, не весь cloud.
    "resource-manager.admin",
  ]
}

resource "yandex_resourcemanager_folder_iam_member" "terraform_sa_roles" {
  for_each  = toset(local.sa_roles)
  folder_id = var.yc_folder_id
  role      = each.value
  member    = "serviceAccount:${yandex_iam_service_account.terraform.id}"
}

# Статический ключ доступа (HMAC) сервисного аккаунта, используется как
# access/secret key для S3-совместимого backend'а Terraform (Object Storage).
resource "yandex_iam_service_account_static_access_key" "terraform_sa_key" {
  service_account_id = yandex_iam_service_account.terraform.id
  description         = "Static key for S3 backend access"
}

# Бакет для хранения state основной конфигурации (terraform-infra).
resource "yandex_storage_bucket" "terraform_state" {
  access_key = yandex_iam_service_account_static_access_key.terraform_sa_key.access_key
  secret_key = yandex_iam_service_account_static_access_key.terraform_sa_key.secret_key
  bucket     = var.state_bucket_name

  versioning {
    enabled = true
  }

  # Явная зависимость от роли storage.admin: без нее бакет иногда пытается
  # создаться раньше, чем роль реально применится, и падает с AccessDenied.
  depends_on = [yandex_resourcemanager_folder_iam_member.terraform_sa_roles]
}
