variable "project_prefix" {
  description = "Project or client prefix"
  type        = string
}

variable "environment" {
  description = "Environment name (prod, uat, dev)"
  type        = string
}

variable "codebuild_role_arn" {
  type = string
}

variable "codebuild_projects" {
  description = "Logical CodeBuild definitions"
  type = map(object({
    buildspec    = string
    compute_type = string
  }))
}