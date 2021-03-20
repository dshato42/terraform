
# AWS RESOURCES PROVISION USING CODE.


## Prerequisits
 * AWS account.
 * AWS Cli instaslled and configured. see link https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2-linux.html
 * AWS IAM Authenticator tool. see link https://docs.aws.amazon.com/eks/latest/userguide/install-aws-iam-authenticator.html
 * wget (required for eks terraform module). 
 * kubectl. see link https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
 * eksctl. see link https://docs.aws.amazon.com/eks/latest/userguide/eksctl.html



## CREATE ECR repository

Create ecr (Elastic container registry)
    
    1. provision using Terraform see [ecr terraform file] ecr-terrafrom.tf.
    
    2. can be created using aws cli using the following commands.
        `aws ecr create-repository --repository-name [REPOSITORY NAME]`


## Create AWS EKS cluster
Provision EKS Cluster
    
    1. Can be created using the aws cli with the following command.
        aws create cluster\
        --name [Name of the cluster]\
        --region [AWS Region Name]\
        --zones [Aws Availability Zones]\
        --node-type [AWS Node Type]\
        --node-min [Min number of nodes]
        --node-max [Max number of nodes]
    
    2. provision using Terraform see [aws eks terraform file] (aws-eks.tf)
