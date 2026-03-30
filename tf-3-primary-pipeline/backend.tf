terraform {
  backend "s3" {
    bucket         = "rm-terraform-states-eu-west-1"
    key            = "GN-non-prod/tf-3-primary-pipeline/terraform.tfstate"
    region         = "eu-west-1"
    dynamodb_table = "terraform-locks"
    encrypt        = true
    profile        = "Depend"
  }
}