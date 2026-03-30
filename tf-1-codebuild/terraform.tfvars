project_prefix = "RM-GN"
environment    = "NON-PROD"

codebuild_role_arn = "arn:aws:iam::938200471346:role/SharedPipelineRole"

codebuild_projects = {

  # ---------- VALIDATORS ----------
  Json-Validator = {
    buildspec    = "build-ymls/json-validator.yml"
    compute_type = "BUILD_GENERAL1_MEDIUM"
  }

  Metadata-Validator = {
    buildspec    = "build-ymls/metadata-validator.yml"
    compute_type = "BUILD_GENERAL1_MEDIUM"
  }

  Client-Package-Validator = {
    buildspec    = "build-ymls/client-package-validator.yml"
    compute_type = "BUILD_GENERAL1_MEDIUM"
  }

  # ---------- COPY & BACKUP ----------
  Copy-Artifacts = {
    buildspec    = "build-ymls/copy-artifacts.yml"
    compute_type = "BUILD_GENERAL1_MEDIUM"
  }

  Backup-Execution = {
    buildspec    = "build-ymls/backup-execution.yml"
    compute_type = "BUILD_GENERAL1_MEDIUM"
  }

  # ---------- CONTROLLERS ----------
  Controller-1 = {
    buildspec    = "build-ymls/controller-1.yml"
    compute_type = "BUILD_GENERAL1_MEDIUM"
  }

  Controller-2 = {
    buildspec    = "build-ymls/controller-2.yml"
    compute_type = "BUILD_GENERAL1_MEDIUM"
  }

  Controller-3 = {
    buildspec    = "build-ymls/controller-3.yml"
    compute_type = "BUILD_GENERAL1_MEDIUM"
  }

  Controller-4 = {
    buildspec    = "build-ymls/controller-4.yml"
    compute_type = "BUILD_GENERAL1_MEDIUM"
  }

  Controller-5 = {
    buildspec    = "build-ymls/controller-5.yml"
    compute_type = "BUILD_GENERAL1_MEDIUM"
  }

 # ---------- CONTROLLERS RETRY----------
  Controller-Retry-1 = {
    buildspec    = "build-ymls/controller-retry-1.yml"
    compute_type = "BUILD_GENERAL1_MEDIUM"
  }

  Controller-Retry-2 = {
    buildspec    = "build-ymls/controller-retry-2.yml"
    compute_type = "BUILD_GENERAL1_MEDIUM"
  }

  Controller-Retry-3 = {
    buildspec    = "build-ymls/controller-retry-3.yml"
    compute_type = "BUILD_GENERAL1_MEDIUM"
  }

  Controller-Retry-4 = {
    buildspec    = "build-ymls/controller-retry-4.yml"
    compute_type = "BUILD_GENERAL1_MEDIUM"
  }

  Controller-Retry-5 = {
    buildspec    = "build-ymls/controller-retry-5.yml"
    compute_type = "BUILD_GENERAL1_MEDIUM"
  }

  # ---------- GATES ----------

  Gate-1 = {
    buildspec    = "build-ymls/gate-check-1.yml"
    compute_type = "BUILD_GENERAL1_SMALL"
  }

  Gate-2 = {
    buildspec    = "build-ymls/gate-check-2.yml"
    compute_type = "BUILD_GENERAL1_SMALL"
  }

  Gate-3 = {
    buildspec    = "build-ymls/gate-check-3.yml"
    compute_type = "BUILD_GENERAL1_SMALL"
  }

  Gate-4 = {
    buildspec    = "build-ymls/gate-check-4.yml"
    compute_type = "BUILD_GENERAL1_SMALL"
  }

# ----------RETRY GATES ----------

  Gate-Retry-1 = {
    buildspec    = "build-ymls/gate-check-retry-1.yml"
    compute_type = "BUILD_GENERAL1_SMALL"
  }

  Gate-Retry-2 = {
    buildspec    = "build-ymls/gate-check-retry-2.yml"
    compute_type = "BUILD_GENERAL1_SMALL"
  }

  Gate-Retry-3 = {
    buildspec    = "build-ymls/gate-check-retry-3.yml"
    compute_type = "BUILD_GENERAL1_SMALL"
  }

  Gate-Retry-4 = {
    buildspec    = "build-ymls/gate-check-retry-4.yml"
    compute_type = "BUILD_GENERAL1_SMALL"
  }


  # ---------- DEPLOY ----------
  Sql-Deploy = {
    buildspec    = "build-ymls/sql-deploy.yml"
    compute_type = "BUILD_GENERAL1_MEDIUM"
  }

  War-Deploy = {
    buildspec    = "build-ymls/war-deploy.yml"
    compute_type = "BUILD_GENERAL1_MEDIUM"
  }

  Linux-Deploy = {
    buildspec    = "build-ymls/linux-deploy.yml"
    compute_type = "BUILD_GENERAL1_MEDIUM"
  }

  Syntax-CT-Deploy = {
    buildspec    = "build-ymls/syntax-ct-deploy.yml"
    compute_type = "BUILD_GENERAL1_MEDIUM"
  }

  CT-Deploy = {
    buildspec    = "build-ymls/ct-deploy.yml"
    compute_type = "BUILD_GENERAL1_MEDIUM"
  }

  TLMView-Deploy = {
    buildspec    = "build-ymls/tlmview-deploy.yml"
    compute_type = "BUILD_GENERAL1_MEDIUM"
  }

  Static-Deploy = {
    buildspec    = "build-ymls/static-deploy.yml"
    compute_type = "BUILD_GENERAL1_MEDIUM"
  }

  Control-Deploy = {
    buildspec    = "build-ymls/control-deploy.yml"
    compute_type = "BUILD_GENERAL1_MEDIUM"
  }
}