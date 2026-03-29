# MarketMate multi-stage deployment process

## General prerequisites
- a working [AWS CLI setup](aws_sso.md) logged in
- [HCP Terraform](https://developer.hashicorp.com/terraform/install) installed 
- MarketMate/backend/infrastructure/terraform.tfvars needs to exists and be filled out with appropriate values

## Stage 1: Deploy bootstrap infrastructure

This stage deploys:
- encrypted, versioned AWS S3 bucket for terraform statefile management
- AWS DynamoDB table to act as a statefile lock file
- AWS ECR container repository

### Steps:

1. Change into the `MarketMate/backend/infrastructure/bootstrap` directory

2. Only one command is needed:
```
terraform apply -var-file="../terraform.tfvars"
```

The statefile of this stage is stored locally and this infrastructure is not destroyed as long as the development enviroenment is used.

3. After this stage is completed, the Docker container of the app can be deployed to the ECR repository as described [here](docker.md).


## Stage 2: Bootstrap database

This stage creates an empty PostgreSQL database and then creates and triggers a Lambda function that uses a python script and the provided SQL script to seed an initial database.

### Steps: 

1. Change into the `MarketMate/backend/infrastructure/bootstrap-db` directory

2. For running scripts on AWS Lambda, we need to ship the dependencies with the python source. That process is called vendoring or to vendor dependencies. For this the dependencies get install directly into the directory of the Lambda script. The bash script `./lambda_task/build.sh` automates that process and needs to be run at least once after every change to the python code of the Lambda Handler.


2. Create and seed database:
```
terraform apply -var-file="../terraform.tfvars"
```

3. The snapshot is created when we terminate the database, so we destroy the bootstrap infrastructure with:

```
terraform destroy
```

From this stage no resources are left, except the snapshot.

## Stage 3: Bootstrap database

Deploy the development environment.

### Steps:

1. Change into the `MarketMate/backend/infrastructure` directory

2. Deploy: 
```
terraform apply
```

After the third stage is completed, four values are displayed in the console output.
- load balancer dns name
- private IP address of docker host 1
- private IP address of docker host 2
- public IP address of NAT instance

SSH access works with:
`ssh -i your-key.pem -J ec2-user@<NAT_PUBLIC_IP> ec2-user@<DOCKER_PRIVATE_IP>`

Web access works with a browser.

