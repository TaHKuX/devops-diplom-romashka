# Сервисные аккаунты, требуемые Managed Service for Kubernetes:
# - один для самого кластера (управление ресурсами облака от имени k8s)
# - один для node group (создание/удаление инстансов нод)
resource "yandex_iam_service_account" "k8s_cluster" {
  name      = "${var.prefix}-k8s-cluster-sa"
  folder_id = var.yc_folder_id
}

resource "yandex_iam_service_account" "k8s_node" {
  name      = "${var.prefix}-k8s-node-sa"
  folder_id = var.yc_folder_id
}

locals {
  k8s_cluster_roles = [
    "k8s.clusters.agent",
    "vpc.publicAdmin",
    "load-balancer.admin",
  ]
  k8s_node_roles = [
    "container-registry.images.puller",
  ]
}

resource "yandex_resourcemanager_folder_iam_member" "k8s_cluster_roles" {
  for_each  = toset(local.k8s_cluster_roles)
  folder_id = var.yc_folder_id
  role      = each.value
  member    = "serviceAccount:${yandex_iam_service_account.k8s_cluster.id}"
}

resource "yandex_resourcemanager_folder_iam_member" "k8s_node_roles" {
  for_each  = toset(local.k8s_node_roles)
  folder_id = var.yc_folder_id
  role      = each.value
  member    = "serviceAccount:${yandex_iam_service_account.k8s_node.id}"
}

# Региональный мастер, ноды в 3 подсетях (по заданию для managed k8s).
resource "yandex_kubernetes_cluster" "main" {
  name       = "${var.prefix}-k8s"
  network_id = yandex_vpc_network.main.id

  master {
    regional {
      region = "ru-central1"

      dynamic "location" {
        for_each = var.zones
        content {
          zone      = location.value
          subnet_id = yandex_vpc_subnet.subnets[location.value].id
        }
      }
    }

    public_ip = true

    security_group_ids = [yandex_vpc_security_group.k8s_main.id]
  }

  service_account_id      = yandex_iam_service_account.k8s_cluster.id
  node_service_account_id = yandex_iam_service_account.k8s_node.id

  release_channel = "REGULAR"

  depends_on = [
    yandex_resourcemanager_folder_iam_member.k8s_cluster_roles,
    yandex_resourcemanager_folder_iam_member.k8s_node_roles,
  ]
}

resource "yandex_kubernetes_node_group" "main" {
  cluster_id = yandex_kubernetes_cluster.main.id
  name       = "${var.prefix}-node-group"

  instance_template {
    platform_id = "standard-v3"

    network_interface {
      nat                = true
      subnet_ids         = [for s in yandex_vpc_subnet.subnets : s.id]
      security_group_ids = [yandex_vpc_security_group.k8s_main.id]
    }

    resources {
      cores         = var.node_resources.cores
      memory        = var.node_resources.memory
      core_fraction = var.node_resources.core_fraction
    }

    boot_disk {
      type = "network-hdd"
      size = 64
    }

    # Прерываемые ВМ для worker-нод, как рекомендовано заданием (дешевле).
    scheduling_policy {
      preemptible = true
    }
  }

  scale_policy {
    fixed_scale {
      size = length(var.zones) * var.node_count_per_zone
    }
  }

  allocation_policy {
    dynamic "location" {
      for_each = var.zones
      content {
        zone = location.value
      }
    }
  }

  maintenance_policy {
    auto_upgrade = true
    auto_repair  = true
  }
}

output "k8s_cluster_id" {
  value = yandex_kubernetes_cluster.main.id
}

output "k8s_external_endpoint" {
  value = yandex_kubernetes_cluster.main.master[0].external_v4_endpoint
}
