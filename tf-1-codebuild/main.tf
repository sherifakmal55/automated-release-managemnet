resource "aws_codebuild_project" "codebuild" {
  for_each = var.codebuild_projects

  name = "${var.project_prefix}-${var.environment}-${each.key}"

  service_role = var.codebuild_role_arn

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    type         = "LINUX_CONTAINER"
    image        = "aws/codebuild/amazonlinux-x86_64-standard:5.0"
    compute_type = each.value.compute_type
  }

  source {
    type      = "CODEPIPELINE"
    buildspec = each.value.buildspec
  }

  logs_config {
    cloudwatch_logs {
      status = "ENABLED"
    }
  }

  build_timeout = 60
}