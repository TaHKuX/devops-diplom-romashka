resource "yandex_container_registry" "main" {
  name      = "${var.prefix}-registry"
  folder_id = var.yc_folder_id
}

# Сервисный аккаунт, от имени которого k8s-нода будет тянуть образы из registry.
resource "yandex_iam_service_account" "puller" {
  name        = "${var.prefix}-registry-puller"
  description = "Used by k8s nodes to pull images from Container Registry"
  folder_id   = var.yc_folder_id
}

resource "yandex_resourcemanager_folder_iam_member" "puller_role" {
  folder_id = var.yc_folder_id
  role      = "container-registry.images.puller"
  member    = "serviceAccount:${yandex_iam_service_account.puller.id}"
}

output "registry_id" {
  value = yandex_container_registry.main.id
}

output "registry_url" {
  value = "cr.yandex/${yandex_container_registry.main.id}"
}
