# How to build and deploy the app docker container
## 1. Log-in to AWS SSO
`aws sso login`
## 2. Authenticate Docker with AWS 
`aws ecr get-login-password --region <region> | docker login --username AWS \
 --password-stdin <aws_account_id>.dkr.ecr.<region>.amazonaws.com`
## 3. Build the image
`docker build -t marketmate-app .`
## 4. Tag image so Docker knows where to push it
`docker tag marketmate-app:latest <aws_account_id>.dkr.ecr.<region>.amazonaws.com/marketmate-app:latest`
## 5. Login to AWS to allow pushing the container to ECR
`aws ecr get-login-password --region <region> | docker login \
  --username AWS \
  --password-stdin <aws_account_id>.dkr.ecr.<region>.amazonaws.com`
## 6. Push the container to AWS
`docker push <aws_account_id>.dkr.ecr.<region>.amazonaws.com/marketmate-app:latest`

## Run the container locally on Linux
`docker run -it --add-host=host.docker.internal:host-gateway -p 5000:5000 marketmate-app`

Explanation of the command options:
- -p outside_port:inside_port

  This adds a port mapping from a port on the localhost interface to a port inside the container.
- --add-host=host.docker.internal:host-gateway

  This adds a new entry to the /etc/host file in the container which maps ip adresses to hostnames. `host.docker.internal` is a host name that can be used to connect to the host ip from inside the container. In Windows/MacOs that resolves automatically to the host ip - in linux an extra entry in /etc/host is needed. `host-gateway` resolves to the host ip (default: 172.17.0.1) on the docker bridge network that the container belongs to.
