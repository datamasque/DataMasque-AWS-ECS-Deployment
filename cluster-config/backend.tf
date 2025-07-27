terraform {
  backend "s3" {
    key            = "datamasque-ecs/tfstate"
    bucket         = "internal-prod-datamasque-infra-tfstate-private-s3"
    dynamodb_table = "mgmt-ap-southeast-2-datamasque-tf-lock"
    acl            = "bucket-owner-full-control"
    region         = "ap-southeast-2"
  }
}
