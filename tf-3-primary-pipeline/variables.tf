variable "project_prefix" {
  description = "Project short name (e.g. GN)"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g. NON-PROD, PROD)"
  type        = string
}

variable "pipeline_role_arn" {
  description = "IAM role ARN used by CodePipeline"
  type        = string
}

variable "artifact_bucket" {
  description = "S3 bucket for CodePipeline artifacts"
  type        = string
}

variable "source_repo" {
  description = "CodeCommit repository for primary pipeline source"
  type        = string
}

variable "source_branch" {
  description = "Branch name for the source repository"
  type        = string
}

