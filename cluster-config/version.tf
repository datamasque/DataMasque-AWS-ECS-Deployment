terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  default_tags {
    tags = {
      # DataMasque AWS PRM (Partner Revenue Measurement) attribution tag. Applied to every
      # taggable resource this deployment provisions so the self-hosted ECS install is attributed.
      "aws-apn-id" = "pc:dp9c56sw1n8t10q5s4pxlgl3x"
    }
  }
}
