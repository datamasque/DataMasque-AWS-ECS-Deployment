terraform {
  backend "s3" {
    key            = "datamasque-ecs/tfstate"
    bucket         = "your-terraform-state-bucket"
    use_lockfile   = true
    acl            = "bucket-owner-full-control"
    region         = "ap-southeast-2"
  }
}
