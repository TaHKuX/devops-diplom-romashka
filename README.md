# DevOps практикум в Yandex Cloud (rtankih)

Структура репозитория:

```
terraform-bootstrap/   сервисный аккаунт + S3-бакет под terraform state, запускается один раз, локальный state
terraform-infra/       основная инфра: VPC, Managed Kubernetes, Container Registry, state в S3
app/                    тестовое nginx-приложение, Dockerfile, CI/CD (GitHub Actions)
k8s/monitoring/         values для kube-prometheus-stack (Prometheus, Grafana, Alertmanager, exporters)
k8s/app/                манифесты Deployment/Service тестового приложения
.github/workflows/      terraform.yml, CI/CD pipeline для инфраструктуры (auto plan/apply при push в main)
```

## 0. Предварительные требования

Установить локально: yc CLI, terraform, kubectl, helm.

```bash
irm https://storage.yandexcloud.net/yandexcloud-yc/install.ps1 | iex
choco install terraform kubernetes-cli kubernetes-helm
```

Авторизация и получение cloud_id/folder_id:

```bash
yc init
yc config list
```

## 1. Bootstrap: сервисный аккаунт и бакет для state

```bash
cd terraform-bootstrap
terraform init

export TF_VAR_yc_token=$(yc iam create-token)
export TF_VAR_yc_cloud_id=<cloud_id>
export TF_VAR_yc_folder_id=<folder_id>
export TF_VAR_state_bucket_name=<уникальное-имя-бакета>

terraform apply
terraform output state_bucket_name
terraform output -raw access_key
terraform output -raw secret_key
```

access_key и secret_key понадобятся как AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY для backend'а основной конфигурации и как секреты GitHub Actions.

## 2. Основная инфраструктура (VPC, Managed Kubernetes, Registry)

```bash
cd ../terraform-infra
cp backend.hcl.example backend.hcl
cp terraform.tfvars.example terraform.tfvars
# вписать в них bucket / cloud_id / folder_id из шага 1

export AWS_ACCESS_KEY_ID=<access_key из шага 1>
export AWS_SECRET_ACCESS_KEY=<secret_key из шага 1>
export TF_VAR_yc_token=$(yc iam create-token)

terraform init -backend-config=backend.hcl
terraform plan
terraform apply
```

После apply:

```bash
yc managed-kubernetes cluster get-credentials $(terraform output -raw k8s_cluster_id) --external --force
kubectl get pods --all-namespaces
```

terraform destroy в этой папке полностью удаляет инфраструктуру без ручных действий.

## 3. Тестовое приложение

Образ собирается и пушится автоматически через .github/workflows/app-docker-build.yml при каждом коммите в main, затрагивающем app/ (тег latest/sha) и при создании тега vX.Y.Z (тег релиза плюс деплой в кластер).

Локальная проверка сборки:

```bash
docker build -t test-app ./app
docker run --rm -p 8080:80 test-app
```

## 4. Мониторинг

quay.io недоступен напрямую из сети Yandex Cloud, поэтому часть образов чарта (prometheus-operator, prometheus, alertmanager, prometheus-config-reloader, node-exporter) заранее перезалита в свой Container Registry под путём `mirror/*` (см. раздел 4a) и переопределена в `k8s/monitoring/values.yaml`. admission-webhook отключен, чтобы не тянуть ghcr.io. Grafana и kube-state-metrics остаются на исходных docker.io/registry.k8s.io - они доступны напрямую.

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

kubectl apply -f k8s/monitoring/namespace.yaml
helm upgrade --install kube-prometheus prometheus-community/kube-prometheus-stack -n monitoring -f k8s/monitoring/values.yaml

kubectl -n monitoring get svc kube-prometheus-grafana
# EXTERNAL-IP этого сервиса - вход в Grafana на 80 порту, логин admin, пароль см. values.yaml
```

## 4a. Перезаливка образов с quay.io в свой registry (один раз, до установки мониторинга)

Нужен Docker Desktop и доступ к quay.io с локальной машины (через VPN, если из РФ напрямую не открывается).

```bash
yc container registry configure-docker

for img in \
  "quay.io/prometheus-operator/prometheus-operator:v0.93.1|prometheus-operator" \
  "quay.io/prometheus-operator/prometheus-config-reloader:v0.93.1|prometheus-config-reloader" \
  "quay.io/prometheus/prometheus:v3.14.0-distroless|prometheus" \
  "quay.io/prometheus/alertmanager:v0.34.0|alertmanager" \
  "quay.io/prometheus/node-exporter:v1.12.1-distroless|node-exporter"
do
  src="${img%%|*}"; name="${img##*|}"; tag="${src##*:}"
  docker pull "$src"
  docker tag "$src" "cr.yandex/crpot29o0cam408r5p0d/mirror/${name}:${tag}"
  docker push "cr.yandex/crpot29o0cam408r5p0d/mirror/${name}:${tag}"
done
```

## 5. Деплой тестового приложения в кластер

```bash
kubectl apply -f k8s/app/namespace.yaml
# перед этим подставить REGISTRY_ID из terraform-infra output registry_id в k8s/app/deployment.yaml
kubectl apply -f k8s/app/deployment.yaml
kubectl apply -f k8s/app/service.yaml

kubectl -n app get svc test-app
# EXTERNAL-IP - адрес приложения на 80 порту
```

## 6. Секреты для GitHub Actions

Settings, Secrets and variables, Actions. Оба workflow (terraform.yml и app-docker-build.yml) лежат в одном репозитории и переиспользуют один ключ сервисного аккаунта terraform-sa (у него уже есть права и на инфраструктуру, и на container-registry).

Получить ключ (id сервисного аккаунта - вывод terraform-bootstrap output service_account_id):
```bash
yc iam key create --service-account-id <service_account_id> --output sa-key.json
```

Секреты:

- YC_SA_KEY_JSON - содержимое sa-key.json целиком
- YC_CLOUD_ID - cloud_id
- YC_FOLDER_ID - folder_id
- TF_STATE_BUCKET - имя бакета из шага 1
- TF_STATE_ACCESS_KEY - access_key из шага 1
- TF_STATE_SECRET_KEY - secret_key из шага 1
- YC_REGISTRY_ID - output registry_id из terraform-infra
- KUBECONFIG_B64 - `cat ~/.kube/config | base64 -w0`

## 7. Что показывать на защите

1. terraform destroy и terraform apply в terraform-bootstrap и terraform-infra - с нуля, без ручных шагов.
2. Скриншоты успешных прогонов terraform.yml в GitHub Actions (plan/apply при коммите в main).
3. Ссылка на собранный образ в Yandex Container Registry.
4. kubectl get pods --all-namespaces без ошибок.
5. Grafana по внешнему IP на 80 порту с дашбордами кластера.
6. Тестовое приложение по внешнему IP на 80 порту.
7. Скриншоты сборки и деплоя app-docker-build.yml при коммите и при создании тега vX.Y.Z.

## Скриншоты и ссылки

### Terraform - создание инфраструктуры с нуля

![terraform apply](docs/screenshots/terraform-apply.png)

### CI/CD - terraform pipeline (GitHub Actions)

![terraform pipeline](docs/screenshots/terraform-pipeline.png)

### Kubernetes кластер

![kubectl get pods](docs/screenshots/kubectl-pods.png)

### Тестовое приложение

Образ: `cr.yandex/crpot29o0cam408r5p0d/test-app:latest`

Ссылка: http://158.160.197.203

![test app](docs/screenshots/test-app.png)

### Grafana

Ссылка: http://158.160.202.106

Логин: `admin`, пароль см. в `k8s/monitoring/values.yaml`

![grafana dashboard](docs/screenshots/grafana-dashboard.png)

### CI/CD - сборка и деплой приложения (GitHub Actions)

![app pipeline commit](docs/screenshots/app-pipeline-commit.png)

![app pipeline tag](docs/screenshots/app-pipeline-tag.png)
