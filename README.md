# Дипломный практикум: DevOps в Yandex Cloud

Отчёт по дипломному заданию. Ниже — что сделано на каждом этапе, какие решения принимались и почему, плюс ссылки/скрины как подтверждение.

Структура репозитория:

```
terraform-bootstrap/   сервисный аккаунт + S3-бакет под terraform state
terraform-infra/       VPC, Managed Kubernetes, Container Registry
app/                    тестовое nginx-приложение + Dockerfile
k8s/monitoring/         values для мониторинга (prometheus-community/kube-prometheus-stack)
k8s/app/                манифесты Deployment/Service тестового приложения
.github/workflows/      CI/CD: terraform.yml и app-docker-build.yml
```

## 1. Облачная инфраструктура

Аккаунт в Yandex Cloud, folder `b1g43km07u2h7cdiscsm`.

Сначала подняли `terraform-bootstrap` - отдельная конфигурация с локальным state (она создаёт сам бакет, поэтому не может хранить свой state в нём же). Создаёт:

- сервисный аккаунт `terraform-sa` с точечным набором ролей (`vpc.admin`, `compute.admin`, `k8s.admin`, `container-registry.admin`, `storage.admin`, `iam.serviceAccounts.user`) - без editor/admin на весь каталог
- статический ключ доступа для S3
- бакет `rtankih-tf-state` (versioning включен) под state основной конфигурации

Дальше `terraform-infra` использует этот бакет как S3-backend и создаёт VPC с тремя подсетями (по одной на зону: a/b/d), security group, managed Kubernetes кластер и Container Registry.

`terraform plan`/`apply`/`destroy` в обеих папках отрабатывают без ручных действий - state в S3, креды через переменные окружения.

Скрин применения с нуля: `docs/screenshots/terraform-apply.png`

## 2. Kubernetes кластер

Выбрали Managed Service for Kubernetes (альтернативный вариант из задания, без Kubespray). По заданию для managed k8s нужен региональный мастер с размещением нод в 3 подсетях - так и сделано (`yandex_kubernetes_cluster.main`, блок `master.regional` с location на каждую зону). Node group - 3 ноды, прерываемые (preemptible), минимальные ресурсы (2 vCPU, 20% core fraction, 2GB) - экономим бюджет купона, как и просили в задании.

```
yc managed-kubernetes cluster get-credentials cat39fdbe2lr0h0mbr94 --external --force
kubectl get pods --all-namespaces
```

отрабатывает без ошибок: `docs/screenshots/kubectl-pods.png`

Прерываемые ВМ для worker-нод, как требует задание: `docs/screenshots/preemptible-nodes.png`

## 3. Тестовое приложение

Простой nginx, отдающий статическую страницу (`app/`). `Dockerfile` собирает образ на `nginx:1.27-alpine`, конфиг в `app/nginx.conf`.

Registry - Yandex Container Registry, создан терраформом вместе с остальной инфрой (`terraform-infra/registry.tf`).

Образ: `cr.yandex/crpot29o0cam408r5p0d/test-app:latest`

## 4. Мониторинг и деплой приложения

Стек - `prometheus-community/kube-prometheus-stack` (Prometheus Operator, Prometheus, Alertmanager, Grafana, kube-state-metrics, node-exporter) через helm, values в `k8s/monitoring/values.yaml`.

Отдельная проблема, с которой пришлось разбираться: часть образов чарта лежит на `quay.io`, который недоступен из сети Yandex Cloud (таймауты на всех нодах, не связано с конкретной зоной или конкретным registry - позже выяснилось, что и часть образов с `registry.k8s.io` тоже не тянется). Пробовали официальное зеркало Yandex `cr.yandex/mirror` - оно проксирует только официальные (library) образы Docker Hub, `bitnami/*` через него не идёт. Пробовали целиком перейти на bitnami-чарты - у них тоже нет полного набора компонентов (нет Grafana в `bitnami/kube-prometheus`). В итоге проблемные образы (prometheus-operator, prometheus, alertmanager, prometheus-config-reloader, node-exporter, kube-state-metrics) вручную перезалиты в свой Container Registry под `cr.yandex/crpot29o0cam408r5p0d/mirror/*` и подставлены через `image.registry`/`image.repository` в values. admission-webhook отключен - тянул ещё один недоступный образ с ghcr.io и не нужен для базовой работы.

Grafana:
- `http://158.160.202.106` (LoadBalancer, порт 80)
- логин `admin`, пароль - см. `prometheus.prometheusSpec` / `grafana.adminPassword` в `k8s/monitoring/values.yaml` (сменить после первого входа)

Тестовое приложение:
- `http://158.160.197.203` (LoadBalancer, порт 80)

Важный нюанс по сети: LoadBalancer в managed k8s шлёт трафик не на порт 80 самой ноды, а на её NodePort (диапазон 30000-32767) - это нужно явно открыть в security group (`terraform-infra/network.tf`), иначе снаружи будет просто таймаут при живых и здоровых подах.

Скрины: `docs/screenshots/kubectl-pods.png`, `docs/screenshots/grafana-dashboard.png`, `docs/screenshots/test-app.png`

## 5. CI/CD: terraform pipeline

Вместо Atlantis/Terraform Cloud - альтернативный вариант из задания: GitHub Actions гоняет `terraform plan`/`apply` при каждом пуше в main, если менялась `terraform-infra/**` (`.github/workflows/terraform.yml`). На pull request - только `plan`, без apply.

Аутентификация: секрет `YC_SA_KEY_JSON` (ключ `terraform-sa`) - workflow сам получает свежий IAM-токен на каждый запуск (`yc iam create-token`), долгоживущий OAuth-токен в секретах не хранится.

Скрин прогона: `docs/screenshots/terraform-pipeline.png`

## 6. CI/CD: сборка и деплой приложения

`.github/workflows/app-docker-build.yml`:

- любой коммит в main, затрагивающий `app/` - сборка образа и пуш с тегом `sha` + `latest`
- тег `vX.Y.Z` - сборка, пуш с этим тегом и деплой в кластер (`kubectl set image`)

Скрины: `docs/screenshots/app-pipeline-commit.png`, `docs/screenshots/app-pipeline-tag.png`

## Как поднять с нуля

```bash
yc init

cd terraform-bootstrap
terraform init
# TF_VAR_yc_token / yc_cloud_id / yc_folder_id / state_bucket_name через переменные окружения
terraform apply

cd ../terraform-infra
cp backend.hcl.example backend.hcl      # вписать bucket
cp terraform.tfvars.example terraform.tfvars   # вписать cloud_id
terraform init -backend-config=backend.hcl
terraform apply

yc managed-kubernetes cluster get-credentials $(terraform output -raw k8s_cluster_id) --external --force

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
kubectl apply -f ../k8s/monitoring/namespace.yaml
helm upgrade --install kube-prometheus prometheus-community/kube-prometheus-stack -n monitoring -f ../k8s/monitoring/values.yaml

docker build -t cr.yandex/crpot29o0cam408r5p0d/test-app:latest ../app
docker push cr.yandex/crpot29o0cam408r5p0d/test-app:latest

kubectl apply -f ../k8s/app/namespace.yaml
kubectl apply -f ../k8s/app/deployment.yaml
kubectl apply -f ../k8s/app/service.yaml
```

Перед первым запуском мониторинга нужно перезалить образы с quay.io/registry.k8s.io в свой registry (см. раздел 4) - иначе поды встанут в ImagePullBackOff.

## Секреты для GitHub Actions

Settings → Secrets and variables → Actions. Оба workflow переиспользуют один ключ сервисного аккаунта `terraform-sa`.

- `YC_SA_KEY_JSON` - `yc iam key create --service-account-id <id из terraform-bootstrap output> --output sa-key.json`, содержимое файла целиком
- `YC_CLOUD_ID`, `YC_FOLDER_ID`
- `TF_STATE_BUCKET`, `TF_STATE_ACCESS_KEY`, `TF_STATE_SECRET_KEY` - из output terraform-bootstrap
- `YC_REGISTRY_ID` - output registry_id из terraform-infra
- `YC_K8S_CLUSTER_ID` - output k8s_cluster_id из terraform-infra (используется job'ом deploy для получения kubeconfig прямо в CI через yc)
