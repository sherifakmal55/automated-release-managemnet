output "deploy_pipeline_names" {
  description = "Names of all deploy pipelines created"
  value = [
    for p in aws_codepipeline.deploy :
    p.name
  ]
}

output "deploy_pipeline_arns" {
  description = "ARNs of all deploy pipelines created"
  value = {
    for key, p in aws_codepipeline.deploy :
    key => p.arn
  }
}