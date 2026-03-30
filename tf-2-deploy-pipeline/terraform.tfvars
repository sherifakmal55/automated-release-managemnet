project_prefix = "RM-GN"
environment    = "NON-PROD"

pipeline_role_arn = "arn:aws:iam::938200471346:role/SharedPipelineRole"
artifact_bucket   = "codepipeline-eu-west-1-110888267db1-4fd2-995e-b908fba16715"

source_repo   = "gn-release-management"
source_branch = "non-prod"

deploy_pipelines = {
  Sql       = {}
  War       = {}
  Control   = {}
  Linux     = {}
  CT        = {}
  SyntaxCT  = {}
  Static    = {}
  TLMView   = {}
}