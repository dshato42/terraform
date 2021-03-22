
provider "aws" {
  profile = "default"
  region  = "us-east-1"
}



data "aws_availability_zones" "azs" {}

data "aws_ami" "aws-linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn-ami-hvm*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}


module "vpc" {
    source = "terraform-aws-modules/vpc/aws"
    version = "2.15.0"
    
    name = "test-vpc"

    cidr = "10.0.0.0/16"
    azs = slice(data.aws_availability_zones.azs.names, 0 ,2)
    public_subnets = ["10.0.1.0/24","10.0.2.0/24" ]
    private_subnets = ["10.0.3.0/24", "10.0.4.0/24"]

    enable_nat_gateway   = true
    single_nat_gateway   = true
    enable_dns_hostnames = true

    tags = {
      Name = "test-vpc" 
    }

}

resource "aws_security_group" "nginx-sg" {
  name   = "nginx-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    description = "Inbound access to ssh port 22 to all"
    from_port   = 22
    protocol    = "tcp"
    to_port     = 22
  }

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    description = "Inbound access to http port 80 only from internal vpc via ELB"
    from_port   = 80
    protocol    = "tcp"
    to_port     = 80
  }

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    description = "outbound to all"
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
  }
}

data "aws_ec2_spot_price" "current" {
  instance_type     = "t2.small"
  availability_zone = module.vpc.azs[0]
  filter {
    name   = "product-description"
    values = ["Linux/UNIX"]
  }
}

resource "aws_spot_instance_request" "spot_worker" {
  ami           = data.aws_ami.aws-linux.id
  spot_price    = data.aws_ec2_spot_price.current.spot_price + data.aws_ec2_spot_price.current.spot_price * 0.2
  instance_type = "t2.small"
  key_name = "my_ssh_key"
  wait_for_fulfillment = true
  spot_type = "one-time"
  subnet_id = module.vpc.public_subnets[0]
  vpc_security_group_ids = [aws_security_group.nginx-sg.id]

  connection {
    type        = "ssh"
    host        = self.public_ip
    user        = "ec2-user"
    private_key = file("/vagrant/my_ssh_key.pem")
  }

  provisioner "remote-exec"  {
       inline = [
       "sudo yum install nginx -y",
       "sudo service nginx start"
    ]
  }

  tags = {
    Name = "CheapWorker"
  }
}

output "spot_instance_id" {
  value = aws_spot_instance_request.spot_worker.spot_instance_id
}

output "spot_instance_public_ip" {
  value = aws_spot_instance_request.spot_worker.public_ip
}

output "spot_instance_public_dns" {
  value = aws_spot_instance_request.spot_worker.public_dns
}

output "spot_price_range" {
  value = data.aws_ec2_spot_price.spot_worker_price
}