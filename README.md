# DataMasque on AWS ECS Fargate

> **Reference blueprint — adapt to your environment.** This repository is a
> starting point, not a turnkey product. Review and harden IAM, networking,
> secrets, and TLS for your own environment before any production use.

DataMasque replaces sensitive production data with synthetically identical
customer data, so teams can build and test against production-shaped data
without exposing PII. This blueprint stands up a self-hosted DataMasque
instance on **AWS ECS Fargate**, with Terraform provisioning the cluster, an
EFS persistent layer, an RDS PostgreSQL application database, service
discovery, and an internal Application Load Balancer. The outcome is a private,
internally reachable DataMasque install you can run masking jobs from. Both the
RDS database and the EFS filesystem are encrypted at rest with the default
AWS-managed KMS key.

**Learn more:** [datamasque.com](https://datamasque.com) ·
[Product docs](https://datamasque.com/portal/documentation/) ·
[Book a demo](https://datamasque.com/request-a-demo)

---

## Getting Started

DataMasque can be deployed on Amazon ECS Fargate using Elastic File System (EFS) as the persistent storage layer.
This repository contains Terraform templates for deploying DataMasque on ECS.

> **Note:** In contrast to other platform deployments,
> the internal database used by the DataMasque application must be deployed as an external PostgreSQL database.
> For this purpose, the Terraform plan deploys an Amazon RDS database within the same VPC as the ECS cluster.

Container images for the DataMasque application running on ECS are available in DataMasque's public ECR:

- `public.ecr.aws/u4t6n7u6/datamasque/admin-frontend`
- `public.ecr.aws/u4t6n7u6/datamasque/app`
- `public.ecr.aws/u4t6n7u6/datamasque/agent-queue`
- `public.ecr.aws/u4t6n7u6/datamasque/in-flight-server`

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

If using private ECR, create the following Amazon ECR repositories
(these mirror the public ECR images this deployment pulls):

- `<ECR host>/<prefix>/admin-frontend`
- `<ECR host>/<prefix>/app`
- `<ECR host>/<prefix>/agent-queue`
- `<ECR host>/<prefix>/in-flight-server`

The `<prefix>` must match the value of `ecrRepoName` in the environment configuration file.

Alternatively, you may configure the deployment to fetch images directly from DataMasque's public ECR repository.

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
    bucket         = "your-terraform-state-bucket"  # replace with your state bucket
    use_lockfile   = true
    acl            = "bucket-owner-full-control"
    region         = "ap-southeast-2"
  }
}
```

The S3 backend bucket must already exist and is **not** created by this
Terraform plan.

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
        deletionProtection: false  # Set true to block accidental RDS deletion (recommended for prod)
        skipFinalSnapshot: true    # Set false to take a final snapshot on destroy
      maskingBuckets: []  # S3 buckets DataMasque may read/write for file masking. Empty = no S3 access granted.
      albCertificate: xxxx-xxxx-xxxx-xxxx-xxxx  # UUID of the certificate in AWS Certificate Manager
      ecr:
        ecrRepoName: datamasque
        ecrImageTag: 3-26-11-0-final-xxxxx  # DataMasque image tag
        ecrRepo: public  # Use "public" to pull from DataMasque's public ECR, or "private" to use your own ECR
      masqueVersion: "3.26.11.0"  # DataMasque version being deployed
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
  ecrImageTag: 3-26-11-0-final-xxxxx  # DataMasque image tag
  ecrRepo: private
```

#### Network Configuration File

The `config/common_configs.yml` file contains environment-specific VPC, subnet, and network settings.
Ensure the environment name matches the Terraform workspace name and the name of the deployment parameters file.

> **Prerequisite:** The RDS DB subnet group named in `db_subnetgroup` is looked
> up, **not created**, by this plan. Create it first (covering the private
> subnets listed in `subnets`) or the apply will fail to find it.

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

## Tearing Down

Run `terraform destroy` to remove the deployment.

> **Irreversible:** `destroy` deletes the RDS instance and the EFS filesystem
> (including all DataMasque metadata, rulesets, and run history). By default
> `skip_final_snapshot = true` and `deletion_protection = false`, so **no final
> snapshot is taken**. For environments you cannot afford to lose, set
> `rds.deletionProtection: true` and `rds.skipFinalSnapshot: false` in your
> environment config (see `config/example.yml`) before applying.

## Next Steps

It is recommended you back up your Terraform configuration files,
for example in a version control system.

For more details including IAM permission requirements and detailed troubleshooting steps,
please refer to the [full DataMasque documentation](https://datamasque.com/portal/documentation/)
(select your DataMasque version, then **Setup** -> **Installation on Amazon ECS**).

---

## Related DataMasque blueprints

- [AWS RDS masking (Step Functions)](https://github.com/datamasque/DataMasque-AWS-RDS-masking-stepfunctions-blueprint)
- [Azure DB masking (Logic Apps)](https://github.com/datamasque/DataMasque-Azure-DB-masking-logicapps-blueprint)
- [AWS Service Catalog DB provisioning](https://github.com/datamasque/DataMasque-AWS-service-catalog-database-provisioning-blueprint)
- [AWS Cross-Account Bucket Access](https://github.com/datamasque/DataMasque-AWS-Cross-Account-Bucket-Access)
- [masque-bricks (Databricks)](https://github.com/datamasque/masque-bricks)
