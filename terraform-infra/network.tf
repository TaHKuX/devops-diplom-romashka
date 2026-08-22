# основная vpc сеть кластера
resource "yandex_vpc_network" "main" {
  name = "${var.prefix}-network"
}

resource "yandex_vpc_subnet" "subnets" {
  for_each = { for idx, zone in var.zones : zone => idx }

  name           = "${var.prefix}-subnet-${each.key}"
  zone           = each.key
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = ["10.${each.value}.0.0/24"]
}

resource "yandex_vpc_security_group" "k8s_main" {
  name       = "${var.prefix}-k8s-main-sg"
  network_id = yandex_vpc_network.main.id

  ingress {
    protocol       = "TCP"
    description    = "Kubernetes API"
    port           = 443
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol       = "TCP"
    description    = "HTTP (nginx / grafana)"
    port           = 80
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol       = "TCP"
    description    = "NodePort диапазон: сюда Network Load Balancer реально шлёт трафик Service type=LoadBalancer"
    from_port      = 30000
    to_port        = 32767
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    protocol          = "ANY"
    description       = "Внутренний трафик между нодами/подами"
    predefined_target = "self_security_group"
    from_port         = 0
    to_port           = 65535
  }

  ingress {
    protocol          = "ANY"
    description       = "Балансировщики нагрузки Yandex Cloud"
    predefined_target = "loadbalancer_healthchecks"
    from_port         = 0
    to_port           = 65535
  }

  egress {
    protocol       = "ANY"
    description    = "Весь исходящий трафик"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}
