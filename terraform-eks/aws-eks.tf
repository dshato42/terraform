##########################
#AWS EKS cluster provision
##########################




variable "region" {
  type = string
  description = "the region to deploy the cluster"
}

variable "env_name" {
  type = string
  description = "The environment name"
}

provider "aws" {
  profile = "default"
  region  = var.region
}


data "aws_availability_zones" "azs" {}

locals {
  cluster_name = "${var.env_name}-cluster"
}


/*
NETWORKING
  create vpc using vpc module
  this module will handle the creation of all the neccecary components for using Netwoking side.
  1. vpc - using the given cidr (10.0.0.0/16) .
  2. subnets - using the private and the public cidrs 10.0.1-4.0/24 (random ciders).
  3. gatway.
  4. route table and with assosiate the table with the subnets.

  NOTE: the tags are required for the eks service to use this vpc
*/
module "vpc" {
    source = "terraform-aws-modules/vpc/aws"
    version = "2.15.0"
    
    name = "${var.env_name}-vpc"

    cidr = "10.0.0.0/16"
    azs = slice(data.aws_availability_zones.azs.names, 0 ,2)
    public_subnets = ["10.0.1.0/24","10.0.2.0/24" ]
    private_subnets = ["10.0.3.0/24", "10.0.4.0/24"]

    enable_nat_gateway   = true
    single_nat_gateway   = true
    enable_dns_hostnames = true

    tags = {
      "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    }
    public_subnet_tags = {
      "kubernetes.io/cluster/${local.cluster_name}" = "shared"
      "kubernetes.io/role/elb"                      = "1"
    }

    private_subnet_tags = {
      "kubernetes.io/cluster/${local.cluster_name}" = "shared"
      "kubernetes.io/role/internal-elb"             = "1"
    }
}

# resource "aws_security_group" "worker-sg" {
#   name   = "worker-sg"
#   vpc_id = module.vpc.vpc_id

#   ingress {
#     cidr_blocks = ["176.229.229.247/24"]
#     description = "Inbound access to ssh port 22 to all"
#     from_port   = 22
#     protocol    = "tcp"
#     to_port     = 22
#   }

#   ingress {
#     cidr_blocks = ["10.0.0.0/16"]
#     description = "Inbound access to http port 80 only from internal vpc via ELB"
#     from_port   = 80
#     protocol    = "tcp"
#     to_port     = 80
#   }

#   egress {
#     cidr_blocks = ["0.0.0.0/0"]
#     description = "outbound to all"
#     from_port   = 0
#     protocol    = "-1"
#     to_port     = 0
#   }
# }

/*
  COMPUTE
  create the eks cluster using the eks module
  this module is responsible for creating all the relevant components for eks cluster to be up and running.
  1. the elb.
  2. configuring the the worker group (worker goup defaults is configured because of a issue with default volume type gp3).
  3. configuring the cluster network using the mentioned above vpc.

*/
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "14.0.0"

  cluster_name    = local.cluster_name
  cluster_version = "1.18"
  subnets         = module.vpc.private_subnets
  vpc_id          = module.vpc.vpc_id
  # worker_additional_security_group_ids = [aws_security_group.worker-sg.id]
  workers_group_defaults = {
    root_volume_type = "gp2"
  }

  worker_groups = [
    {
      instance_type = "t2.micro"
      asg_desired_capacity  = 1
      asg_max_size          = 3
      asg_min_size          = 1
    }
  ]
}

# data object to feed the configure kubernetes provider
data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

# save the kube config file in kube/config file
resource "local_file" "kubeconfig" {
    content     = module.eks.kubeconfig
    filename = "~/.kube/config"
    depends_on = [module.eks]
}

# echot the nodes status
resource "null_resource" "example1" {
  provisioner "local-exec" {
    command = "kubectl get nodes -owide"
  }
  depends_on = [local_file.kubeconfig]
}

# outputing the kube config content to the screen at the end of the provisioning
output "kubectl_config" {
  description = "kubectl config that can be used to authenticate with the cluster"
  value       = module.eks.kubeconfig
}


