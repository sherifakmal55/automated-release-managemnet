terraform {
  backend "s3" {
    bucket         = "rm-terraform-states-eu-west-1"
    key            = "GN-non-prod/tf-1-codebuild/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
    profile        = "Depend"
  }
}