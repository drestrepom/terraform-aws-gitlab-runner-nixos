# GitLab Runner Configuration
resource "gitlab_user_runner" "nixos_runner" {
  runner_type = "project_type"
  project_id  = var.gitlab_project_id

  description = var.gitlab_runner_description
  tag_list    = var.gitlab_runner_tags
  untagged    = var.gitlab_runner_untagged
}

# GitLab Runner outputs
output "gitlab_runner_id" {
  value       = gitlab_user_runner.nixos_runner.id
  description = "GitLab Runner ID"
}

output "gitlab_runner_token" {
  value       = gitlab_user_runner.nixos_runner.token
  description = "GitLab Runner authentication token"
  sensitive   = true
}

output "gitlab_runner_runner_type" {
  value       = gitlab_user_runner.nixos_runner.runner_type
  description = "GitLab Runner type"
}

output "gitlab_project_id" {
  value       = var.gitlab_project_id
  description = "GitLab Project ID where the runner is registered"
}

