locals {
  name_prefix = "${var.project_prefix}-${var.environment}"
}

resource "aws_codepipeline" "primary" {
  name     = "${local.name_prefix}-Release-Management-Pipeline"
  role_arn = var.pipeline_role_arn

  artifact_store {
    location = var.artifact_bucket
    type     = "S3"
  }

  ##################################################
  # SOURCE
  ##################################################
  stage {
    name = "${local.name_prefix}-Source"

    action {
      name             = "${local.name_prefix}-Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeCommit"
      version          = "1"
      output_artifacts = ["SourceArtifact"]

      configuration = {
        RepositoryName       = var.source_repo
        BranchName           = var.source_branch
        PollForSourceChanges = false

        
      }
    }
  }

  ##################################################
  # VALIDATION
  ##################################################
  stage {
    name = "${local.name_prefix}-Json-Validator"

    action {
      name     = "${local.name_prefix}-Json-Validator"
      category = "Build"
      owner    = "AWS"
      provider = "CodeBuild"
      version  = "1"

      input_artifacts  = ["SourceArtifact"]
      output_artifacts = ["ValidatedOutput"]

      configuration = {
        ProjectName = "${local.name_prefix}-Json-Validator"

        EnvironmentVariables = jsonencode([
          {
            name  = "PIPELINE_EXECUTION_ID"
            value = "#{codepipeline.PipelineExecutionId}"
            type  = "PLAINTEXT"
          },
          {
            name  = "STAGE_NAME"
            value = "Json-Validator"
            type  = "PLAINTEXT"
          }
        ])
      }
    }
  }

  ##################################################
  # CLIENT PACKAGE VALIDATOR
  ##################################################

  stage {
    name = "${local.name_prefix}-Client-Package-Validator"

    action {
      name     = "${local.name_prefix}-Client-Package-Validator"
      category = "Build"
      owner    = "AWS"
      provider = "CodeBuild"
      version  = "1"

      input_artifacts = ["SourceArtifact", "ValidatedOutput"]

      configuration = {
        ProjectName   = "${local.name_prefix}-Client-Package-Validator"
        PrimarySource = "SourceArtifact"

        EnvironmentVariables = jsonencode([
          {
            name  = "PIPELINE_EXECUTION_ID"
            value = "#{codepipeline.PipelineExecutionId}"
            type  = "PLAINTEXT"
          },
          {
            name  = "STAGE_NAME"
            value = "Client-Package-Validator"
            type  = "PLAINTEXT"
          }
        ])
      }
    }
  }

  stage {
    name = "${local.name_prefix}-Metadata-Validator"

    action {
      name     = "${local.name_prefix}-Metadata-Validator"
      category = "Build"
      owner    = "AWS"
      provider = "CodeBuild"
      version  = "1"

      input_artifacts = ["SourceArtifact", "ValidatedOutput"]

      configuration = {
        ProjectName   = "${local.name_prefix}-Metadata-Validator"
        PrimarySource = "SourceArtifact"

        EnvironmentVariables = jsonencode([
          {
            name  = "PIPELINE_EXECUTION_ID"
            value = "#{codepipeline.PipelineExecutionId}"
            type  = "PLAINTEXT"
          },
          {
            name  = "STAGE_NAME"
            value = "Metadata-Validator"
            type  = "PLAINTEXT"
          }
        ])
      }
    }
  }


  ##################################################
  # PRE-DEPLOY
  ##################################################
  stage {
    name = "${local.name_prefix}-Copy-Artifacts"

    action {
      name     = "${local.name_prefix}-Copy-Artifacts"
      category = "Build"
      owner    = "AWS"
      provider = "CodeBuild"
      version  = "1"

      input_artifacts = ["SourceArtifact", "ValidatedOutput"]

      configuration = {
        ProjectName   = "${local.name_prefix}-Copy-Artifacts"
        PrimarySource = "SourceArtifact"

        EnvironmentVariables = jsonencode([
          {
            name  = "PIPELINE_EXECUTION_ID"
            value = "#{codepipeline.PipelineExecutionId}"
            type  = "PLAINTEXT"
          },
          {
            name  = "STAGE_NAME"
            value = "Copy-Artifacts"
            type  = "PLAINTEXT"
          }
        ])
      }
    }
  }

  stage {
    name = "${local.name_prefix}-Backup-Execution"

    action {
      name     = "${local.name_prefix}-Backup-Execution"
      category = "Build"
      owner    = "AWS"
      provider = "CodeBuild"
      version  = "1"

      input_artifacts = ["SourceArtifact", "ValidatedOutput"]

      configuration = {
        ProjectName   = "${local.name_prefix}-Backup-Execution"
        PrimarySource = "SourceArtifact"

        EnvironmentVariables = jsonencode([
          {
            name  = "PIPELINE_EXECUTION_ID"
            value = "#{codepipeline.PipelineExecutionId}"
            type  = "PLAINTEXT"
          },
          {
            name  = "STAGE_NAME"
            value = "Backup-Execution"
            type  = "PLAINTEXT"
          }
        ])
      }
    }
  }

  ##################################################
  # DEPLOY APPROVAL
  ##################################################
  stage {
    name = "${local.name_prefix}-Approval-To-Deploy"

    action {
      name     = "${local.name_prefix}-Manual-Approval-To-Deploy"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"

      configuration = {
        ExternalEntityLink = "https://eu-west-1.console.aws.amazon.com/s3/buckets/nonprod-release-management-codebuild-logs?region=eu-west-1&prefix=pipeline-logs/#{codepipeline.PipelineExecutionId}/Backup-Execution/"
      }
    }
  }

  ##################################################
  # CONTROLLER / GATE / APPROVAL — LOOP 1
  ##################################################
  stage {
    name = "${local.name_prefix}-Controller-1"

    action {
      name            = "${local.name_prefix}-Controller-1"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceArtifact" , "ValidatedOutput"]

      namespace = "gate1"

      configuration = {
        ProjectName = "${local.name_prefix}-Controller-1"
        PrimarySource = "SourceArtifact"

        EnvironmentVariables = jsonencode([
          {
            name  = "PIPELINE_EXECUTION_ID"
            value = "#{codepipeline.PipelineExecutionId}"
            type  = "PLAINTEXT"
          },
          {
            name  = "STAGE_NAME"
            value = "Controller-1"
            type  = "PLAINTEXT"
          }
        ])
      }
    }
  }

  stage {
    name = "${local.name_prefix}-Gate-1"

    action {
      name            = "${local.name_prefix}-Gate-1"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceArtifact" , "ValidatedOutput"]

      configuration = {
        ProjectName = "${local.name_prefix}-Gate-1"
        PrimarySource = "SourceArtifact"

        EnvironmentVariables = jsonencode([
          {
             name  = "NEED_APPROVAL"
            value = "#{gate1.NEED_APPROVAL}"
            type  = "PLAINTEXT"
          },
          {
            name  = "PIPELINE_EXECUTION_ID"
            value = "#{codepipeline.PipelineExecutionId}"
            type  = "PLAINTEXT"
          },
          {
            name  = "STAGE_NAME"
            value = "Gate-1"
            type  = "PLAINTEXT"
          }
          ])
        }
      }
  }
  

  stage {
    name = "${local.name_prefix}-Gate-1-Approval"

    action {
      name     = "${local.name_prefix}-Gate-1-Manual-Approval"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"

      configuration = {
        ExternalEntityLink = "https://eu-west-1.console.aws.amazon.com/s3/buckets/nonprod-release-management-codebuild-logs?region=eu-west-1&prefix=pipeline-logs/#{codepipeline.PipelineExecutionId}/Controller-1/"
      }
    }
  }

  ##################################################
  # CONTROLLER RETRY / GATE / APPROVAL — LOOP 1 RETRY
  ##################################################
  stage {
    name = "${local.name_prefix}-Controller-Retry-1"

    action {
      name            = "${local.name_prefix}-Controller-Retry-1"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceArtifact" , "ValidatedOutput"]

      namespace = "gate1retry"

      configuration = {
        ProjectName = "${local.name_prefix}-Controller-Retry-1"
        PrimarySource = "SourceArtifact"

        EnvironmentVariables = jsonencode([
          {
            name  = "PIPELINE_EXECUTION_ID"
            value = "#{codepipeline.PipelineExecutionId}"
            type  = "PLAINTEXT"
          },
          {
            name  = "STAGE_NAME"
            value = "Controller-Retry-1"
            type  = "PLAINTEXT"
          }
        ])
      }
    }
  }

  stage {
    name = "${local.name_prefix}-Gate-Retry-1"

    action {
      name            = "${local.name_prefix}-Gate-Retry-1"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceArtifact" , "ValidatedOutput"]

      configuration = {
        ProjectName = "${local.name_prefix}-Gate-Retry-1"
        PrimarySource = "SourceArtifact"

        EnvironmentVariables = jsonencode([
          {
             name  = "NEED_APPROVAL"
            value = "#{gate1retry.NEED_APPROVAL}"
            type  = "PLAINTEXT"
          },
          {
            name  = "PIPELINE_EXECUTION_ID"
            value = "#{codepipeline.PipelineExecutionId}"
            type  = "PLAINTEXT"
          },
          {
            name  = "STAGE_NAME"
            value = "Gate-Retry-1"
            type  = "PLAINTEXT"
          }
          ])
        }
      }
  }
  

  stage {
    name = "${local.name_prefix}-Gate-Retry-1-Approval"

    action {
      name     = "${local.name_prefix}-Gate-Retry-1-Manual-Approval"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"

      configuration = {
        ExternalEntityLink = "https://eu-west-1.console.aws.amazon.com/s3/buckets/nonprod-release-management-codebuild-logs?region=eu-west-1&prefix=pipeline-logs/#{codepipeline.PipelineExecutionId}/Controller-Retry-1/"
      }
    }
  }

  ##################################################
  # CONTROLLER / GATE / APPROVAL — LOOP 2
  ##################################################
  stage {
    name = "${local.name_prefix}-Controller-2"

    action {
      name            = "${local.name_prefix}-Controller-2"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceArtifact" , "ValidatedOutput"]

      namespace = "gate2"

      configuration = {
        ProjectName = "${local.name_prefix}-Controller-2"
        PrimarySource = "SourceArtifact"

        EnvironmentVariables = jsonencode([
          {
            name  = "PIPELINE_EXECUTION_ID"
            value = "#{codepipeline.PipelineExecutionId}"
            type  = "PLAINTEXT"
          },
          {
            name  = "STAGE_NAME"
            value = "Controller-2"
            type  = "PLAINTEXT"
          }
        ])
      }
    }
  }

  stage {
    name = "${local.name_prefix}-Gate-2"

    action {
      name            = "${local.name_prefix}-Gate-2"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceArtifact" , "ValidatedOutput"]

      configuration = {
        ProjectName = "${local.name_prefix}-Gate-2"
        PrimarySource = "SourceArtifact"

        EnvironmentVariables = jsonencode([
          {
             name  = "NEED_APPROVAL"
            value = "#{gate2.NEED_APPROVAL}"
            type  = "PLAINTEXT"
          },
          {
            name  = "PIPELINE_EXECUTION_ID"
            value = "#{codepipeline.PipelineExecutionId}"
            type  = "PLAINTEXT"
          },
          {
            name  = "STAGE_NAME"
            value = "Gate-2"
            type  = "PLAINTEXT"
          }
          ])
      }
    }
  }

  stage {
    name = "${local.name_prefix}-Gate-2-Approval"

    action {
      name     = "${local.name_prefix}-Gate-2-Manual-Approval"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"

      configuration = {
        ExternalEntityLink = "https://eu-west-1.console.aws.amazon.com/s3/buckets/nonprod-release-management-codebuild-logs?region=eu-west-1&prefix=pipeline-logs/#{codepipeline.PipelineExecutionId}/Controller-2/"
      }
    }
  }

##################################################
  # CONTROLLER RETRY / GATE / APPROVAL — LOOP 2 RETRY
  ##################################################
  stage {
    name = "${local.name_prefix}-Controller-Retry-2"

    action {
      name            = "${local.name_prefix}-Controller-Retry-2"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceArtifact" , "ValidatedOutput"]

      namespace = "gate2retry"

      configuration = {
        ProjectName = "${local.name_prefix}-Controller-Retry-2"
        PrimarySource = "SourceArtifact"

        EnvironmentVariables = jsonencode([
          {
            name  = "PIPELINE_EXECUTION_ID"
            value = "#{codepipeline.PipelineExecutionId}"
            type  = "PLAINTEXT"
          },
          {
            name  = "STAGE_NAME"
            value = "Controller-Retry-2"
            type  = "PLAINTEXT"
          }
        ])
      }
    }
  }

  stage {
    name = "${local.name_prefix}-Gate-Retry-2"

    action {
      name            = "${local.name_prefix}-Gate-Retry-2"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceArtifact" , "ValidatedOutput"]

      configuration = {
        ProjectName = "${local.name_prefix}-Gate-Retry-2"
        PrimarySource = "SourceArtifact"

        EnvironmentVariables = jsonencode([
          {
             name  = "NEED_APPROVAL"
            value = "#{gate2retry.NEED_APPROVAL}"
            type  = "PLAINTEXT"
          },
          {
            name  = "PIPELINE_EXECUTION_ID"
            value = "#{codepipeline.PipelineExecutionId}"
            type  = "PLAINTEXT"
          },
          {
            name  = "STAGE_NAME"
            value = "Gate-Retry-2"
            type  = "PLAINTEXT"
          }
          ])
      }
    }
  }

  stage {
    name = "${local.name_prefix}-Gate-Retry-2-Approval"

    action {
      name     = "${local.name_prefix}-Gate-Retry-2-Manual-Approval"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"

      configuration = {
        ExternalEntityLink = "https://eu-west-1.console.aws.amazon.com/s3/buckets/nonprod-release-management-codebuild-logs?region=eu-west-1&prefix=pipeline-logs/#{codepipeline.PipelineExecutionId}/Controller-Retry-2/"
      }
    }
  }

  ##################################################
  # CONTROLLER / GATE / APPROVAL — LOOP 3
  ##################################################
  stage {
    name = "${local.name_prefix}-Controller-3"

    action {
      name            = "${local.name_prefix}-Controller-3"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceArtifact" , "ValidatedOutput"]

      namespace = "gate3"


      configuration = {
        ProjectName = "${local.name_prefix}-Controller-3"
        PrimarySource = "SourceArtifact"

        EnvironmentVariables = jsonencode([
          {
            name  = "PIPELINE_EXECUTION_ID"
            value = "#{codepipeline.PipelineExecutionId}"
            type  = "PLAINTEXT"
          },
          {
            name  = "STAGE_NAME"
            value = "Controller-3"
            type  = "PLAINTEXT"
          }
        ])
      }
    }
  }

  stage {
    name = "${local.name_prefix}-Gate-3"

    action {
      name            = "${local.name_prefix}-Gate-3"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceArtifact" , "ValidatedOutput"]



      configuration = {
        ProjectName = "${local.name_prefix}-Gate-3"
        PrimarySource = "SourceArtifact"

        EnvironmentVariables = jsonencode([
          {
             name  = "NEED_APPROVAL"
            value = "#{gate3.NEED_APPROVAL}"
            type  = "PLAINTEXT"
          },
          {
            name  = "PIPELINE_EXECUTION_ID"
            value = "#{codepipeline.PipelineExecutionId}"
            type  = "PLAINTEXT"
          },
          {
            name  = "STAGE_NAME"
            value = "Gate-3"
            type  = "PLAINTEXT"
          }
          ])
      }
    }
  }

  stage {
    name = "${local.name_prefix}-Gate-3-Approval"

    action {
      name     = "${local.name_prefix}-Gate-3-Manual-Approval"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"

      configuration = {
        ExternalEntityLink = "https://eu-west-1.console.aws.amazon.com/s3/buckets/nonprod-release-management-codebuild-logs?region=eu-west-1&prefix=pipeline-logs/#{codepipeline.PipelineExecutionId}/Controller-3/"
      }
    }
  }

##################################################
  # CONTROLLER RETRY / GATE / APPROVAL — LOOP 3 RETRY
  ##################################################
  stage {
    name = "${local.name_prefix}-Controller-Retry-3"

    action {
      name            = "${local.name_prefix}-Controller-Retry-3"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceArtifact" , "ValidatedOutput"]

      namespace = "gate3retry"


      configuration = {
        ProjectName = "${local.name_prefix}-Controller-Retry-3"
        PrimarySource = "SourceArtifact"

        EnvironmentVariables = jsonencode([
          {
            name  = "PIPELINE_EXECUTION_ID"
            value = "#{codepipeline.PipelineExecutionId}"
            type  = "PLAINTEXT"
          },
          {
            name  = "STAGE_NAME"
            value = "Controller-Retry-3"
            type  = "PLAINTEXT"
          }
        ])
      }
    }
  }

  stage {
    name = "${local.name_prefix}-Gate-Retry-3"

    action {
      name            = "${local.name_prefix}-Gate-Retry-3"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceArtifact" , "ValidatedOutput"]



      configuration = {
        ProjectName = "${local.name_prefix}-Gate-Retry-3"
        PrimarySource = "SourceArtifact"

        EnvironmentVariables = jsonencode([
          {
             name  = "NEED_APPROVAL"
            value = "#{gate3retry.NEED_APPROVAL}"
            type  = "PLAINTEXT"
          },
          {
            name  = "PIPELINE_EXECUTION_ID"
            value = "#{codepipeline.PipelineExecutionId}"
            type  = "PLAINTEXT"
          },
          {
            name  = "STAGE_NAME"
            value = "Gate-Retry-3"
            type  = "PLAINTEXT"
          }
          ])
      }
    }
  }

  stage {
    name = "${local.name_prefix}-Gate-Retry-3-Approval"

    action {
      name     = "${local.name_prefix}-Gate-Retry-3-Manual-Approval"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"

      configuration = {
        ExternalEntityLink = "https://eu-west-1.console.aws.amazon.com/s3/buckets/nonprod-release-management-codebuild-logs?region=eu-west-1&prefix=pipeline-logs/#{codepipeline.PipelineExecutionId}/Controller-Retry-3/"
      }
    }
  }

  ##################################################
  # CONTROLLER / GATE / APPROVAL — LOOP 4
  ##################################################
  stage {
    name = "${local.name_prefix}-Controller-4"

    action {
      name            = "${local.name_prefix}-Controller-4"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceArtifact" , "ValidatedOutput"]

      namespace = "gate4"


      configuration = {
        ProjectName = "${local.name_prefix}-Controller-4"
        PrimarySource = "SourceArtifact"

        EnvironmentVariables = jsonencode([
          {
            name  = "PIPELINE_EXECUTION_ID"
            value = "#{codepipeline.PipelineExecutionId}"
            type  = "PLAINTEXT"
          },
          {
            name  = "STAGE_NAME"
            value = "Controller-4"
            type  = "PLAINTEXT"
          }
        ])
      }
    }
  }

  stage {
    name = "${local.name_prefix}-Gate-4"

    action {
      name            = "${local.name_prefix}-Gate-4"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceArtifact" , "ValidatedOutput"]

      configuration = {
        ProjectName = "${local.name_prefix}-Gate-4"
        PrimarySource = "SourceArtifact"

        EnvironmentVariables = jsonencode([
          {
             name  = "NEED_APPROVAL"
            value = "#{gate4.NEED_APPROVAL}"
            type  = "PLAINTEXT"
          },
          {
            name  = "PIPELINE_EXECUTION_ID"
            value = "#{codepipeline.PipelineExecutionId}"
            type  = "PLAINTEXT"
          },
          {
            name  = "STAGE_NAME"
            value = "Gate-4"
            type  = "PLAINTEXT"
          }
          ])
      }
    }
  }

  stage {
    name = "${local.name_prefix}-Gate-4-Approval"

    action {
      name     = "${local.name_prefix}-Gate-4-Manual-Approval"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"

      configuration = {
        ExternalEntityLink = "https://eu-west-1.console.aws.amazon.com/s3/buckets/nonprod-release-management-codebuild-logs?region=eu-west-1&prefix=pipeline-logs/#{codepipeline.PipelineExecutionId}/Controller-4/"
      }
    }
  }

##################################################
  # CONTROLLER RETRY / GATE / APPROVAL — LOOP 4 RETRY
  ##################################################
  stage {
    name = "${local.name_prefix}-Controller-Retry-4"

    action {
      name            = "${local.name_prefix}-Controller-Retry-4"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceArtifact" , "ValidatedOutput"]

      namespace = "gate4retry"


      configuration = {
        ProjectName = "${local.name_prefix}-Controller-Retry-4"
        PrimarySource = "SourceArtifact"

        EnvironmentVariables = jsonencode([
          {
            name  = "PIPELINE_EXECUTION_ID"
            value = "#{codepipeline.PipelineExecutionId}"
            type  = "PLAINTEXT"
          },
          {
            name  = "STAGE_NAME"
            value = "Controller-Retry-4"
            type  = "PLAINTEXT"
          }
        ])
      }
    }
  }

  stage {
    name = "${local.name_prefix}-Gate-Retry-4"

    action {
      name            = "${local.name_prefix}-Gate-Retry-4"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceArtifact" , "ValidatedOutput"]

      configuration = {
        ProjectName = "${local.name_prefix}-Gate-Retry-4"
        PrimarySource = "SourceArtifact"

        EnvironmentVariables = jsonencode([
          {
             name  = "NEED_APPROVAL"
            value = "#{gate4retry.NEED_APPROVAL}"
            type  = "PLAINTEXT"
          },
          {
            name  = "PIPELINE_EXECUTION_ID"
            value = "#{codepipeline.PipelineExecutionId}"
            type  = "PLAINTEXT"
          },
          {
            name  = "STAGE_NAME"
            value = "Gate-Retry-4"
            type  = "PLAINTEXT"
          }
          ])
      }
    }
  }

  stage {
    name = "${local.name_prefix}-Gate-Retry-4-Approval"

    action {
      name     = "${local.name_prefix}-Gate-Retry-4-Manual-Approval"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"

      configuration = {
        ExternalEntityLink = "https://eu-west-1.console.aws.amazon.com/s3/buckets/nonprod-release-management-codebuild-logs?region=eu-west-1&prefix=pipeline-logs/#{codepipeline.PipelineExecutionId}/Controller-Retry-4/"
      }
    }
  }

  ##################################################
  # CONTROLLER / GATE / APPROVAL — LOOP 5
  ##################################################
  stage {
    name = "${local.name_prefix}-Controller-5"

    action {
      name            = "${local.name_prefix}-Controller-5"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceArtifact" , "ValidatedOutput"]

      namespace = "gate5"

      configuration = {
        ProjectName = "${local.name_prefix}-Controller-5"
        PrimarySource = "SourceArtifact"

        EnvironmentVariables = jsonencode([
          {
            name  = "PIPELINE_EXECUTION_ID"
            value = "#{codepipeline.PipelineExecutionId}"
            type  = "PLAINTEXT"
          },
          {
            name  = "STAGE_NAME"
            value = "Controller-5"
            type  = "PLAINTEXT"
          }
        ])
      }
    }
  }

  stage {
    name = "${local.name_prefix}-Gate-5"

    action {
      name            = "${local.name_prefix}-Gate-5"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceArtifact" , "ValidatedOutput"]

      configuration = {
        ProjectName = "${local.name_prefix}-Gate-5"
        PrimarySource = "SourceArtifact"

        EnvironmentVariables = jsonencode([
          {
             name  = "NEED_APPROVAL"
            value = "#{gate5.NEED_APPROVAL}"
            type  = "PLAINTEXT"
          },

          {
            name  = "PIPELINE_EXECUTION_ID"
            value = "#{codepipeline.PipelineExecutionId}"
            type  = "PLAINTEXT"
          },
          {
            name  = "STAGE_NAME"
            value = "Gates-5"
            type  = "PLAINTEXT"
          }
          ])
      }
    }
  }

  stage {
    name = "${local.name_prefix}-Gate-5-Approval"

    action {
      name     = "${local.name_prefix}-Gate-5-Manual-Approval"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"

      configuration = {
        ExternalEntityLink = "https://eu-west-1.console.aws.amazon.com/s3/buckets/nonprod-release-management-codebuild-logs?region=eu-west-1&prefix=pipeline-logs/#{codepipeline.PipelineExecutionId}/Controller-5/"
      }
    }
  }


  ##################################################
  # CONTROLLER RETRY / GATE / APPROVAL — LOOP 5 RETRY
  ##################################################
  stage {
    name = "${local.name_prefix}-Controller-Retry-5"

    action {
      name            = "${local.name_prefix}-Controller-Retry-5"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceArtifact" , "ValidatedOutput"]

      namespace = "gate5retry"

      configuration = {
        ProjectName = "${local.name_prefix}-Controller-Retry-5"
        PrimarySource = "SourceArtifact"

        EnvironmentVariables = jsonencode([
          {
            name  = "PIPELINE_EXECUTION_ID"
            value = "#{codepipeline.PipelineExecutionId}"
            type  = "PLAINTEXT"
          },
          {
            name  = "STAGE_NAME"
            value = "Controller-Retry-5"
            type  = "PLAINTEXT"
          }
        ])
      }
    }
  }

  stage {
    name = "${local.name_prefix}-Gate-Retry-5"

    action {
      name            = "${local.name_prefix}-Gate-Retry-5"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      version         = "1"
      input_artifacts = ["SourceArtifact" , "ValidatedOutput"]

      configuration = {
        ProjectName = "${local.name_prefix}-Gate-Retry-5"
        PrimarySource = "SourceArtifact"

        EnvironmentVariables = jsonencode([
          {
             name  = "NEED_APPROVAL"
            value = "#{gate5retry.NEED_APPROVAL}"
            type  = "PLAINTEXT"
          },

          {
            name  = "PIPELINE_EXECUTION_ID"
            value = "#{codepipeline.PipelineExecutionId}"
            type  = "PLAINTEXT"
          },
          {
            name  = "STAGE_NAME"
            value = "Gate-Retry-5"
            type  = "PLAINTEXT"
          }
          ])
      }
    }
  }

  stage {
    name = "${local.name_prefix}-Gate-Retry-5-Approval"

    action {
      name     = "${local.name_prefix}-Gate-Retry-5-Manual-Approval"
      category = "Approval"
      owner    = "AWS"
      provider = "Manual"
      version  = "1"

      configuration = {
        ExternalEntityLink = "https://eu-west-1.console.aws.amazon.com/s3/buckets/nonprod-release-management-codebuild-logs?region=eu-west-1&prefix=pipeline-logs/#{codepipeline.PipelineExecutionId}/Controller-Retry-5/"
      }
    }
  }
}