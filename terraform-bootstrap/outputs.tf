output "service_account_id" {
  value = yandex_iam_service_account.terraform.id
}

output "state_bucket_name" {
  value = yandex_storage_bucket.terraform_state.bucket
}

output "access_key" {
  value     = yandex_iam_service_account_static_access_key.terraform_sa_key.access_key
  sensitive = true
}

output "secret_key" {
  value     = yandex_iam_service_account_static_access_key.terraform_sa_key.secret_key
  sensitive = true
}
