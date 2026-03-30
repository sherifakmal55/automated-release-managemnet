#########################################
# Locals - Auto generate CodeBuild names
#########################################
locals {
  deploy_pipelines = {
    for key, val in var.deploy_pipelines :
    key => merge(val, {
      codebuild_name = (
        try(val.codebuild_name, null) != null ?
        val.codebuild_name :
        "${var.project_prefix}-${var.environment}-${key}-Deploy"
      )
    })
  }
}

resource "aws_codepipeline" "deploy" {
  for_each = local.deploy_pipelines

  name = format(
    "%s-%s-%s-Pipeline",
    var.project_prefix,
    var.environment,
    each.key
  )

  role_arn = var.pipeline_role_arn

  artifact_store {
    type     = "S3"
    location = var.artifact_bucket
  }

  ################################
  # Source Stage
  ################################
  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"

      output_artifacts = ["SourceArtifact"]

      configuration = {
        RepositoryName       = var.source_repo
        BranchName           = var.source_branch
        PollForSourceChanges = "false"
        OutputArtifactFormat = "CODE_ZIP"
      }
    }
  }

  ################################
  # Build Stage
  ################################
  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"

      input_artifacts  = ["SourceArtifact"]
      output_artifacts = ["BuildArtifact"]

      configuration = {
        ProjectName = each.value.codebuild_name

        EnvironmentVariables = jsonencode([
          {
            name  = "JIRA_ID"
            value = "#{variables.JIRA_ID}"
            type  = "PLAINTEXT"
          },
          {
            name  = "TASK_INDEX"
            value = "#{variables.TASK_INDEX}"
            type  = "PLAINTEXT"
          },
          {
            name  = "TASK_TYPE"
            value = "#{variables.TASK_TYPE}"
            type  = "PLAINTEXT"
          },
          {
            name  = "PARENT_EXECUTION_ID"
            value = "#{variables.PARENT_EXECUTION_ID}"
            type  = "PLAINTEXT"
          },
          {
            name  = "STAGE_NAME"
            value = "${each.key}-Deploy"
            type  = "PLAINTEXT"
          }
        ])
      }
    }
  }

  ################################
  # Pipeline Variables (V2)
  ################################
  variable {
    name = "JIRA_ID"
  }

  variable {
    name = "TASK_INDEX"
  }

  variable {
    name = "TASK_TYPE"
  }

  variable {
    name = "PARENT_EXECUTION_ID"
  }

  pipeline_type = "V2"
}