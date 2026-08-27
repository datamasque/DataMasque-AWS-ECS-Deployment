locals {
  ecs_config        = yamldecode(file("../config/${terraform.workspace}.yml"))
  common_config     = yamldecode(file("../config/common_configs.yml"))
  common_env_config = local.common_config[terraform.workspace]

  ecr_image_url = {
    for cluster_key, cluster_config in lookup(local.ecs_config["ecs"], "clusters", {}) : cluster_key => {
      is_public  = cluster_config["ecr"]["ecrRepo"] == "public"
      account_id = cluster_config["ecr"]["ecrRepo"] == "public" ? null : data.aws_caller_identity.current.account_id
      region     = cluster_config["ecr"]["ecrRepo"] == "public" ? null : data.aws_region.current.name
      repo_base  = cluster_config["ecr"]["ecrRepo"] == "public" ? "u4t6n7u6/datamasque" : cluster_config["ecr"]["ecrRepoName"]
      image_tag  = cluster_config["ecr"]["ecrImageTag"]
    }
  }

  # ECR base URL for all images
  # Public ECR: `public.ecr.aws/<repo prefix>`
  # Private ECR: `<account ID>.dkr.ecr.<region>.amazonaws.com/<repo prefix>`
  ecr_base_url = {
    for cluster_key in keys(local.ecr_image_url) : cluster_key =>
    local.ecr_image_url[cluster_key].is_public ?
    "public.ecr.aws/${local.ecr_image_url[cluster_key].repo_base}" :
    "${local.ecr_image_url[cluster_key].account_id}.dkr.ecr.${local.ecr_image_url[cluster_key].region}.amazonaws.com/${local.ecr_image_url[cluster_key].repo_base}"
  }

  agent_table_reference_storage_gib = {
    for cluster_key, cluster_config in lookup(local.ecs_config["ecs"], "clusters", {}) :
    cluster_key => lookup(cluster_config["agentContainer"], "tableReferenceStorageGiB", 20)
  }

  agent_ephemeral_storage_headroom_gib = 5

  # Fargate refuses an ephemeral storage size below 21 GiB.
  agent_ephemeral_storage_gib = {
    for cluster_key, storage_gib in local.agent_table_reference_storage_gib :
    cluster_key => max(21, storage_gib + local.agent_ephemeral_storage_headroom_gib)
  }
}
