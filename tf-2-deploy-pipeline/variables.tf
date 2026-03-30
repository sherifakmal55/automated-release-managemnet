variable "project_prefix" {
  type = string
}

variable "environment" {
  type = string
}

variable "pipeline_role_arn" {
  type = string
}

variable "artifact_bucket" {
  type = string
}

variable "source_repo" {
  description = "Shared dummy CodeCommit repo used as source for all deploy pipelines"
  type        = string
}

variable "source_branch" {
  description = "Branch name for dummy CodeCommit source"
  type        = string
}

variable "deploy_pipelines" {
  description = "Deploy pipelines mapped to their CodeBuild projects"
  type = map(object({
    codebuild_name = optional(string)
  }))
}