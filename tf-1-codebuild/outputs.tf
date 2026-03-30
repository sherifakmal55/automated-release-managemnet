output "codebuild_project_names" {
  value = {
    for k, v in aws_codebuild_project.codebuild :
    k => v.name
  }
}