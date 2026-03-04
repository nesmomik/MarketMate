# MarketMate

> More documentation at the upstream repository:  [AWS_grocery](https://github.com/AlejandroRomanIbanez/AWS_grocery)
 
## Educational project to learn cloud topics 
- [AWS infrastructure](#aws-infrastructure)
    - EC2
    - S3
    - RDS
    - DynamoDB
    - ECR
- [Docker](#docker)
- [Terraform](#terraform)

## Summary

MarketMate is an educational e-commerce platform based on the Python Flask and Javascript React Framework. The goal of the project was to deploy a development environment for the e-commerce platform on AWS. It was implemented by packaging the app in a docker container, deploying it on two EC2 instances in private subnets behind a Load Balancer und connecting them to a RDS PostgreSQL instance in a private subnet group. Container Images are pulled automatically from an ECR repository and user images are stored in a S3 bucket. An additional instance acts as a NAT instance to allow internet access for the docker host and as a jump box to allow SSH access to the docker hosts. The usage of Terraform to define the infrastructure as code simplifies the creation and destruction of the development environment.

## AWS infrastructure

### Overview
- three EC2 compute t3.micro instances with latest Amazon Linux 2023 AMIx86-64
    - two configured as docker hosts
    - one configured as NAT instance / bastion host 
- RDS database t3.micro instance configured by loading a snapshot
- Application Load Balancer with basic blocklist and target group containing the docker hosts
- S3 object storage bucket 
- ECR container registry repository

```mermaid
graph TD
    %% External Entities
    Developer[👨‍💻 Developer]
    User[👤 User]
    
    %% Public Layer
    NAT[🛡️ NAT Instance / Bastion]
    ALB[🌐 Load Balancer]
    
    %% Private Layer
    Docker1[🐳 Docker Host 1]
    Docker2[🐳 Docker Host 2]
    
    %% AWS Managed Services
    RDS[🗄️ RDS Database]
    ECR[📦 ECR Repository]
    S3[🪣 S3 Avatars Bucket]

    %% Connections
    Developer -- SSH --> NAT
    User -- HTTP --> ALB
    
    NAT -- SSH --> Docker1
    NAT -- SSH --> Docker2
    
    ALB -- HTTP --> Docker1
    ALB -- HTTP --> Docker2

    Docker1 -- R/W Data --> RDS
    Docker2 -- R/W Data --> RDS

    Docker1 -- Pull Containers --> ECR
    Docker2 -- Pull Containers --> ECR

    Docker1 -- Get/Put Images --> S3
    Docker2 -- Get/Put Images --> S3
```

### Networking
- Custom VPC spanning two availability zones (eu-central-1a, eu-central-1b) with:
    - public subnets for the Application Load Balancer and NAT/Bastion instance
    - private subnets for the docker hosts
    - DB subnet group spanning both private subnets for the RDS instance
    - Each subnet has to be linked to a route table, and a subnet can only be linked to one route table. On the other hand, one route table can have associations with multiple subnets. Every VPC has a default route table, and it is a good practice to leave it in its original state and create a new route table to customize the network traffic routes associated with your VPC. 
    
``` mermaid
graph TD
    %% Internet Connection
    Internet((🌐 The Internet))
    IGW[🚪 Internet Gateway]

    %% VPC Definition
    subgraph VPC [🏰 VPC: 10.0.0.0/16]
        direction TB

        %% Route Tables
        PublicRT[🔀 Public Route Table <br/> 0.0.0.0/0 -> IGW]
        PrivateRT[🔀 Private Route Table <br/> 0.0.0.0/0 -> NAT Instance]

        %% Public Subnets
        subgraph PublicZone [🌍 Public Zone]
            direction LR
            subgraph Public [🌍 Public Zone]
                PubSub1A[🟩 Public Subnet 1a <br/> 10.0.1.0/24 <br/> eu-central-1a]
                NAT[🛡️ NAT Instance <br/> 'marketmate-nat-instance']
            end
            subgraph Publiic [🌍 Public Zone]
                PubSub1B[🟩 Public Subnet 1b <br/> 10.0.2.0/24 <br/> eu-central-1b]
            end 
        end

        %% Private Subnets
        subgraph PrivateZone [🔒 Private Zone]
            direction LR
            PrivSub1A[🟥 Private Subnet 1a <br/> 10.0.11.0/24 <br/> eu-central-1a]
            PrivSub1B[🟥 Private Subnet 1b <br/> 10.0.12.0/24 <br/> eu-central-1b]
            
            %% Key Components in Private Subnets
            Docker1[🐳 Docker Host 1]
            Docker2[🐳 Docker Host 2]
        end

        %% Physical Placements
        PubSub1A -. Contains .-> NAT
        PrivSub1A -. Contains .-> Docker1
        PrivSub1B -. Contains .-> Docker2

        %% Routing Associations
        PublicRT ==>|Routes Traffic For| PubSub1A
        PublicRT ==>|Routes Traffic For| PubSub1B
        
        PrivateRT ==>|Routes Traffic For| PrivSub1A
        PrivateRT ==>|Routes Traffic For| PrivSub1B
    end

    %% External Connections
    Internet <--> IGW
    IGW <--> PublicRT
    
    %% Internal Routing Flows
    NAT -->|Outbound NAT Traffic| PublicRT
    PrivateRT -->|0.0.0.0/0| NAT

```
- security groups:
    - docker_app_flask_sg
        - ingress: "5000/tcp/load_balancer_sg"
        - ingress: "22/tcp/net_bastion_sg"
        - egress: "all/-1/0.0.0.0/0"
    - nat_bastion_sg
        - ingress: "5000/tcp/0.0.0.0/0"
        - ingress: "22/tcp/{dev_public_ip}/32"
        - egress: "all/-1/nat_bastion_sg"
    - rds_sg
        - ingress: "5432/tcp/docker_app_flask_sg"
    - load_balancer_sg
        - ingress: "80/tcp/0.0.0.0/0"
        - egress: "all/-1/0.0.0.0/0"

``` mermaid
graph TD
    %% External Entities
    Developer[👨‍💻 Developer's IP <br/> local.my_public_ip/32]
    Internet[🌐 The Internet <br/> 0.0.0.0/0]
    VPC_CIDR[🏰 Entire VPC <br/> 10.0.0.0/16]

    %% Security Groups
    subgraph SG_ALB [ALB Security Group <br/> 'lb-sg']
        ALB[Application Load Balancer]
    end

    subgraph SG_NAT [NAT / Bastion Security Group <br/> 'nat-bastion-sg']
        NAT[NAT / Bastion Instance]
    end

    subgraph SG_APP [Docker Hosts Security Group <br/> 'app-sg']
        Docker[Docker Hosts 1 & 2]
    end

    subgraph SG_RDS [RDS Security Group <br/> 'rds-sg']
        RDS[PostgreSQL Database]
    end

    %% ==========================================
    %% INGRESS RULES (What's allowed IN)
    %% ==========================================
    
    %% ALB Ingress
    Internet -- "['lb-sg']<br/>Ingress: Port 80 (HTTP)" --> SG_ALB
    
    %% NAT/Bastion Ingress
    Developer -- "['nat-bastion-sg']<br/>Ingress: Port 22 (SSH)" --> SG_NAT
    VPC_CIDR -- "['nat-bastion-sg']<br/>Ingress: All Traffic (-1)" --> SG_NAT
    
    %% Docker Hosts Ingress
    SG_ALB -- "['app-sg']<br/>Ingress: Port 5000 (TCP)" --> SG_APP
    SG_NAT -- "['app-sg']<br/>Ingress: Port 22 (SSH)" --> SG_APP
    
    %% RDS Ingress
    SG_APP -- "['rds-sg']<br/>Ingress: Port 5432 (Postgres)" --> SG_RDS


    %% ==========================================
    %% EGRESS RULES (What's allowed OUT)
    %% ==========================================
    
    %% Outbound connections
    SG_ALB -. "['lb-sg']<br/>Egress: All Traffic (0.0.0.0/0)" .-> Internet
    SG_NAT -. "['nat-bastion-sg']<br/>Egress: All Traffic (0.0.0.0/0)" .-> Internet
    SG_APP -. "['app-sg']<br/>Egress: All Traffic (0.0.0.0/0)" .-> Internet
    

    %% Styling
    classDef sg fill:#f9f9f9,stroke:#333,stroke-width:2px,stroke-dasharray: 5 5;
    class SG_ALB,SG_NAT,SG_APP,SG_RDS sg;
    
    classDef external fill:#e1f5fe,stroke:#01579b,stroke-width:2px;
    class Developer,Internet,VPC_CIDR external;
```

### Permission Management
- IAM policies attached to the docker hosts:
    - S3 get/put/list
    - ECR read only
    - Systems Manager

## Docker


## Terraform