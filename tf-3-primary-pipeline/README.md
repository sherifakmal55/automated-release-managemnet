TF-3 – Primary Release Pipeline

Design:
- Controllers perform deployment orchestration
- Gates replace entry conditions
- Manual approval after every gate
- No UI-based logic

Benefits:
- 100% Terraform managed
- Reusable for multiple clients
- No drift



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
