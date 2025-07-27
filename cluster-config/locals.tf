locals {
  ecs_config        = yamldecode(file("../config/${terraform.workspace}.yml"))
  common_config     = yamldecode(file("../config/common_configs.yml"))
  common_env_config = local.common_config[terraform.workspace]
  
}
