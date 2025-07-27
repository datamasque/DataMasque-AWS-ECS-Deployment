# DM ECS Deployment



## Getting started

DataMasque can be deployed on Amazon ECS Fargate using Elastic File System (EFS) as the persistent storage layer. In contrast to other platform deployments, the internal database used DataMasque application must be deployed as an external PostgreSQL database, preferably using Amazon RDS within the same VPC as the application.

 

Container images for the DataMasque application running on ECS can be either pushed to your account’s Amazon ECR (Elastic Container Registry) OR they can be consumed from DataMasque’s public ECR repositories - 


`ap-southeast-2` - 
```
269378400967.dkr.ecr.ap-southeast-2.amazonaws.com/datamasque/admin-db
269378400967.dkr.ecr.ap-southeast-2.amazonaws.com/datamasque/admin-frontend
269378400967.dkr.ecr.ap-southeast-2.amazonaws.com/datamasque/admin-server
269378400967.dkr.ecr.ap-southeast-2.amazonaws.com/datamasque/agent
269378400967.dkr.ecr.ap-southeast-2.amazonaws.com/datamasque/agent-queue
269378400967.dkr.ecr.ap-southeast-2.amazonaws.com/datamasque/in-flight-server
```

`us-east-1` -
```
269378400967.dkr.ecr.us-east-1.amazonaws.com/datamasque/admin-db
269378400967.dkr.ecr.us-east-1.amazonaws.com/datamasque/admin-frontend
269378400967.dkr.ecr.us-east-1.amazonaws.com/datamasque/admin-server
269378400967.dkr.ecr.us-east-1.amazonaws.com/datamasque/agent
269378400967.dkr.ecr.us-east-1.amazonaws.com/datamasque/agent-queue
269378400967.dkr.ecr.us-east-1.amazonaws.com/datamasque/in-flight-server
```


## Deployment Overview

This  Terrafrom based deployment process automates the creation of the following resources: - 


- ECS Fargate cluster
- ECS Services and Task Definitions
- EFS filesystem and access point
- Required IAM roles for ECS tasks
- Amazon RDS PostgreSQL instance
- Security groups for ECS and RDS
- AWS Cloud Map service discovery namespace and service entries


##Prerequisite
Before starting the deployment, ensure the following tools are installed:

- [ ] [aws CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)

- [ ] [Terraform](https://developer.hashicorp.com/terraform/install)

Additionally, create the following Amazon ECR repositories (if using private ECR):- 

- repo_prefix/admin-frontend
- repo_prefix/admin-server
- repo_prefix/agent
- repo_prefix/agent-queue
- repo_prefix/in-flight-server

The repo_prefix must match the value of ecrRepoName in the environment_name.yaml configuration.

Alternatively, you may configure the deployment to fetch images directly from DataMasque’s public ECR repositories in us-east-1 or ap-southeast-2.



## Deployment Steps

1. Clone the deployment repository - 

```
git clone https://github.com/datamasque/DataMasque-AWS-ECS-Deployment.git
cd DataMasque-AWS-ECS-Deployment 
```

2. Update the parameters specific to Terraform State in backend.tf file based on your environment. For more information please visit - [HashiCorp Developer](https://developer.hashicorp.com/terraform/language/backend/s3) 
Below is the example backend.tf, please replace the parameter values based on your environment. 

```
terraform {
  backend "s3" {
    key            = "datamasque-ecs/tfstate"
    bucket         = "Bucket_name"
    dynamodb_table = "dynamodb-tf-lock"
    acl            = "bucket-owner-full-control"
    region         = "ap-southeast-2"
  }
}
```

3. Update config yaml files - 

`environment_name.yaml`

This file defines deployment parameters specific to your environment. The filename (e.g., dev.yaml) must match the Terraform workspace name.

```
ecs:
  # clusters: {}
  clusters:
    datamasque-ecs: #Name of the ECS fargate cluster.
      dnsNamespace: datamasque #Cloudmap namespace
      rds:
        multiAz: false
      ecr:
        ecrRepoName: datamasque #ECR repo prefix name
        ecrImageTag: 2-25-1-preview-0-19931 #DataMasque image tag
        ecrRepo: public # Valid values are public / private. Images are fetched from DataMasque's public repo if set to public.
        ecrRepoRegion: ap-southeast-2 #AWS region to fetch repos, valid only if ecrRepo is set to public
      masqueVersion: "2.27.0" #DataMasque version being deployed
      loggingLevel: "INFO" #DataMasque logging level
      agentContainer:
        cpu: 512  #CPU allocation for DataMasque agent container
        memory: 2048 #Memory allocation for DataMasque agent container
        desiredCount: 1 # Number of agent containers to deploy
      inflightContainer:
        cpu: 512 #CPU allocation for DataMasque inflight container
        memory: 2048 #Memory allocation for DataMasque inflight container
        desiredCount: 1 # Number of inflight containers to deploy

```


`common_configs.yaml`

This file contains environment-specific VPC, subnet, and network settings. Ensure the environment name matches the Terraform workspace and environment_name.yaml mentioned above.

```
dev:
  vpcid: "vpc-xxxx" #VPC ID where DataMasque being deployed
  db_subnetgroup: "db subnet group" #Name of the db subnet group to deploy RDS
  ingress_cidr: 10.x.x.x/x #CIDR range to allow connections to DataMasque application
  subnets: #Subnet IDs in the VPC
    subnetb: "subnet-0axxxx" #2b private subnet
    subnetc: "subnet-04xxxx" # 2c: private subnet
    subneta: "subnet-0axxxx" #2a: private subnet

prod:
  vpcid: "vpc-xxxx"
  db_subnetgroup: "db subnet group" #Name of the db subnet group to deploy RDS
  db_subnetgroup: private-db-subnetgroup
  ingress_cidr: 10.x.x.x/x
  subnets:
    subnetb: "subnet-0axxxx" #2b private subnet
    subnetc: "subnet-04xxxx" # 2c: private subnet
    subneta: "subnet-0axxxx" #2a: private subnet
```

4. Deploy DataMasque. 

```
export AWS_PROFILE=profile_name
cd cluster-config
terraform init
terraform workspace select -or-create dev
terraform plan
terraform apply
```