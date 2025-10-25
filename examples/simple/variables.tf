variable "gitlab_token" {
  description = "GitLab Personal Access Token with 'create_runner' scope"
  type        = string
  sensitive   = true
}

variable "gitlab_project_id" {
  description = "GitLab Project ID where the runner will be registered"
  type        = number
}

