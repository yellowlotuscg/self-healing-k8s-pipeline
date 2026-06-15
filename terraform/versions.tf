# Provider pins. I keep these tight - drifting provider versions has burned me
# in real Terraform repos, so the demo models the same discipline.
#
# NOTE: terraform isn't installed in the build environment, so this is
# validated-by-review, not `terraform validate`. The HCL is written to plan
# cleanly against a local Docker + kind setup.
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    # tehcyx/kind is the de-facto provider for managing kind clusters from TF.
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.5"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.14"
    }
  }
}
