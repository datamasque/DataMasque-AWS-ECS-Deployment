locals {
  ecs_config        = yamldecode(file("../config/${terraform.workspace}.yml"))
  common_config     = yamldecode(file("../config/common_configs.yml"))
  common_env_config = local.common_config[terraform.workspace]

  ecr_image_url = {
    for cluster_key, cluster_config in lookup(local.ecs_config["ecs"], "clusters", {}) : cluster_key => {
      account_id = cluster_config["ecr"]["ecrRepo"] == "public" ? "269378400967" : data.aws_caller_identity.current.account_id
      region     = cluster_config["ecr"]["ecrRepo"] == "public" ? cluster_config["ecr"]["ecrRepoRegion"] : data.aws_region.current.name
      repo_base  = cluster_config["ecr"]["ecrRepo"] == "public" ? "datamasque" : cluster_config["ecr"]["ecrRepoName"]
      image_tag  = cluster_config["ecr"]["ecrImageTag"]
    }
  }

  # ECR base URL for all images (`<account ID>.dkr.ecr.<region>.amazonaws.com/<repo prefix>`)
  ecr_base_url = {
    for cluster_key in keys(local.ecr_image_url) : cluster_key =>
      "${local.ecr_image_url[cluster_key].account_id}.dkr.ecr.${local.ecr_image_url[cluster_key].region}.amazonaws.com/${local.ecr_image_url[cluster_key].repo_base}"
  }
}
