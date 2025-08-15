# DataMasque Installation on AWS Elastic Container Service (ECS) Fargate

## Getting Started

DataMasque can be deployed on Amazon ECS Fargate using Elastic File System (EFS) as the persistent storage layer.
This repository contains Terraform templates for deploying DataMasque on ECS.

> **Note:** In contrast to other platform deployments,
> the internal database used by the DataMasque application must be deployed as an external PostgreSQL database.
> For this purpose, the Terraform plan deploys an Amazon RDS database within the same VPC as the ECS cluster.

Container images for the DataMasque application running on ECS are available in DataMasque's public ECRs
in the `ap-southeast-2` and `us-east-1` regions.

- `ap-southeast-2`:
  - `269378400967.dkr.ecr.ap-southeast-2.amazonaws.com/datamasque/admin-frontend`
  - `269378400967.dkr.ecr.ap-southeast-2.amazonaws.com/datamasque/admin-server`
  - `269378400967.dkr.ecr.ap-southeast-2.amazonaws.com/datamasque/agent`
  - `269378400967.dkr.ecr.ap-southeast-2.amazonaws.com/datamasque/agent-queue`
  - `269378400967.dkr.ecr.ap-southeast-2.amazonaws.com/datamasque/in-flight-server`
- `us-east-1`:
  - `269378400967.dkr.ecr.us-east-1.amazonaws.com/datamasque/admin-frontend`
  - `269378400967.dkr.ecr.us-east-1.amazonaws.com/datamasque/admin-server`
  - `269378400967.dkr.ecr.us-east-1.amazonaws.com/datamasque/agent`
  - `269378400967.dkr.ecr.us-east-1.amazonaws.com/datamasque/agent-queue`
  - `269378400967.dkr.ecr.us-east-1.amazonaws.com/datamasque/in-flight-server`

## Deployment Overview

This Terraform-based deployment process automates the creation of the following resources:

- ECS Fargate cluster
- ECS Services and Task Definitions
- EFS filesystem and access point
- Required IAM roles for ECS tasks
- Amazon RDS PostgreSQL instance
- Security groups for ECS and RDS
- AWS Cloud Map service discovery namespace and service entries

## Prerequisites

### Required Software

Before starting the deployment, ensure the following software is installed:

- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [Terraform](https://developer.hashicorp.com/terraform/install)
- [git](https://git-scm.com/downloads)

### Private ECR Setup (Optional)

If using private ECR, create the following Amazon ECR repositories:

- `<ECR host>/<prefix>/admin-db`
- `<ECR host>/<prefix>/admin-frontend`
- `<ECR host>/<prefix>/admin-server`
- `<ECR host>/<prefix>/agent`
- `<ECR host>/<prefix>/agent-queue`
- `<ECR host>/<prefix>/in-flight-server`

The `<prefix>` must match the value of `ecrRepoName` in the environment configuration file.

Alternatively, you may configure the deployment to fetch images directly from DataMasque's public ECR repositories in `us-east-1` or `ap-southeast-2`.

## Deployment Steps

### Step 1: Clone the Terraform Repository

Use `git` to obtain a local checkout of DataMasque's Terraform repository.

```bash
git clone https://github.com/datamasque/DataMasque-AWS-ECS-Deployment.git
cd DataMasque-AWS-ECS-Deployment
```

### Step 2: Update Terraform Backend Configuration

Update the parameters specific to Terraform State in the `cluster-config/backend.tf` file based on your environment.
For more information, refer to the Terraform documentation:
[https://developer.hashicorp.com/terraform/language/backend/s3](https://developer.hashicorp.com/terraform/language/backend/s3)

Below is the example `backend.tf`. Replace the parameter values based on your environment. 

```hcl
terraform {
  backend "s3" {
    key            = "datamasque-ecs/tfstate"
    bucket         = "bucket-name"
    use_lockfile   = true
    acl            = "bucket-owner-full-control"
    region         = "ap-southeast-2"
  }
}
```

### Step 3: Update Configuration Files

Update the YAML configuration files to match your environment.

#### Environment Configuration File

The `config/<environment_name>.yml` file defines deployment parameters specific to your environment.
The filename must exactly match the Terraform workspace name, plus `.yml` extension.
For example, if the workspace is called `production`,
create a file named `production.yml` in the `config` directory.

The example shown below is for the public ECR:

```yaml
ecs:
  clusters:
    datamasque-ecs:  # Name of the ECS Fargate cluster. NB: It is not possible to change this after deployment.
      dnsNamespace: datamasque  # AWS Cloud Map namespace. NB: It is not possible to change this after deployment.
      rds:
        multiAz: false
      albCertificate: xxxx-xxxx-xxxx-xxxx-xxxx  # UUID of the certificate in AWS Certificate Manager
      ecr:
        ecrRepoName: datamasque
        ecrImageTag: 2-28-0-final-xxxxx  # DataMasque image tag
        ecrRepo: public
        ecrRepoRegion: ap-southeast-2  # AWS region to fetch images from (ap-southeast-2 or us-east-1)
      masqueVersion: "2.28.0"  # DataMasque version being deployed
      loggingLevel: "INFO"  # DataMasque logging level
      agentContainer:
        cpu: 2048  # CPU allocation for DataMasque agent container (in units, where 1024 = one vCPU)
        memory: 4096  # Memory allocation for DataMasque agent container (in MB)
        desiredCount: 1  # Number of agent containers to deploy
      inflightContainer:
        cpu: 512  # CPU allocation for DataMasque inflight container (in units)
        memory: 2048  # Memory allocation for DataMasque inflight container (in MB)
        desiredCount: 1  # Number of inflight containers to deploy
```

> **Note:** It is not possible to change the name of the cluster or DNS namespace after deployment.

> **Note**: The above specifications
> (2 vCPUs and 4GB RAM for the DataMasque agent,
> and 0.5 vCPUs and 2GB RAM for in-flight masking)
> are the minimum supported values.
> You can increase these resource allowances if required.

For a private ECR, edit the `ecr` block as follows:

```yaml
ecr:
  ecrRepoName: <prefix>  # Your ECR repo prefix from above
  ecrImageTag: 2-28-0-final-xxxxx  # DataMasque image tag
  ecrRepo: private
  # Omit the ecrRepoRegion field - not required for private ECR
```

#### Network Configuration File

The `config/common_configs.yml` file contains environment-specific VPC, subnet, and network settings.
Ensure the environment name matches the Terraform workspace name and the name of the deployment parameters file.

```yaml
production:
  vpcid: "vpc-xxxx"  # VPC ID where DataMasque is being deployed
  db_subnetgroup: "datamasque-db-subnet-group"  # Name of the db subnet group in which to deploy RDS. Must already exist.
  inbound_cidr_range: 10.0.0.0/16  # CIDR range to allow connections to DataMasque application
  subnets:  # Subnet IDs in the VPC. At least one subnet is required.
    subneta: "subnet-xxxx"
    subnetb: "subnet-yyyy"
    subnetc: "subnet-zzzz"
```

For `subnets`, at least one subnet is required;
normally there are three, one for each availability zone in your AWS region.
The subnet IDs can be viewed in your VPC configuration in AWS Console;
they have the form `subnet-xxxx` where `xxxx` is a 17-character hexadecimal string.

### Step 4: Deploy DataMasque

Select the correct AWS profile and Terraform workspace, then execute `terraform plan`.
The Terraform workspace name must match the naming of the environment configuration file
and content of the network configuration file,
as per the above instructions.

```shell
export AWS_PROFILE=<AWS profile name>
cd cluster-config
terraform init
terraform workspace select -or-create production
terraform plan
```

If the above commands succeed, `terraform plan` should show that there are 50 resources to be created.
Verify the output looks correct,
then run `terraform apply` to create the ECS cluster.
The `apply` operation takes about 5-10 minutes.

Once deployed, you can access DataMasque through the Application Load Balancer internal hostname.

## Next Steps

It is recommended you back up your Terraform configuration files,
for example in a version control system.

For more details including IAM permission requirements and detailed troubleshooting steps,
please refer to the [full DataMasque documentation](https://datamasque.com/portal/documentation/)
(select your DataMasque version, then **Setup** -> **Installation on Amazon ECS**).
