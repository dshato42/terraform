
# VARIABLES #
variable "region" {}
variable "vpc_cider" {}
variable "public_subnet" {}
variable "private_subnet" {}
variable "tag" {}
variable "key_name" {}
variable "key_path" {}
variable "instance_type" {}
variable "instance_count" {}
variable "aws_access_key" {}
variable "aws_secret_key" {}
# VARIABLES #

# PROVIDERS #
provider "aws" {
  profile = "arcusteam"
  region  = "us-east-1"
}
# PROVIDERS #



# DATA #
data "aws_availability_zones" "azs" {}

data "aws_ami" "ubuntu-ami" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_ec2_spot_price" "current" {
  instance_type     = var.instance_type
  availability_zone = module.vpc.azs[0]
  filter {
    name   = "product-description"
    values = ["Linux/UNIX"]
  }
}

# DATA #


# RESOURCES
resource "aws_iam_role" "ec2-iam-role" {
  name = "ec2-iam-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
  tags = {
    "name" = "${var.tag}-ec2-iam-role"
  }
}

resource "aws_iam_role_policy_attachment" "allow_sqs_full" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSQSFullAccess"
  role       = aws_iam_role.ec2-iam-role.name
}

resource "aws_iam_instance_profile" "instance_profile" {
  name = "test_instance_profile"
  role = aws_iam_role.ec2-iam-role.name
}



module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.15.0"

  name = "test-vpc"

  cidr            = var.vpc_cider
  azs             = slice(data.aws_availability_zones.azs.names, 0, 2)
  public_subnets  = [var.public_subnet]
  private_subnets = [var.private_subnet]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.tag}-vpc"
  }

}

resource "aws_security_group" "ssh-sg" {
  name   = "ssh-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    description = "Inbound access to ssh port 22 to all"
    from_port   = 22
    protocol    = "tcp"
    to_port     = 22
  }

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    description = "outbound to all"
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
  }

  tags = {
    "Name" = "${var.tag}-ssh-sg"
  }
}

resource "aws_sqs_queue" "incoming-queue" {
  name                        = "incoming-queue.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  tags = {
    "Name" = "${var.tag}-incoming-queue"
  }
}

resource "aws_sqs_queue" "outgoing-queue" {
  name                        = "outgoing-queue.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  tags = {
    "Name" = "${var.tag}-outgoing-queue"
  }
}


resource "aws_spot_instance_request" "worker" {
  count                  = var.instance_count
  ami                    = data.aws_ami.ubuntu-ami.id
  spot_price             = data.aws_ec2_spot_price.current.spot_price
  instance_type          = var.instance_type
  key_name               = var.key_name
  wait_for_fulfillment   = true
  spot_type              = "one-time"
  subnet_id              = module.vpc.public_subnets[0]
  vpc_security_group_ids = [aws_security_group.ssh-sg.id]
  # iam_instance_profile   = aws_iam_instance_profile.instance_profile.name

  connection {
    type        = "ssh"
    host        = self.public_ip
    user        = "ubuntu"
    private_key = file(var.key_path)
  }

  provisioner "file" {
    source      = "./message_handler.py"
    destination = "/home/ubuntu/message_handler.py"

  }


  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install unzip -y",
      "sudo apt install python3 -y",
      "sudo apt-get -y install python3-pip",
      "pip3 install boto3",
      "curl https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o awscliv2.zip",
      "unzip awscliv2.zip",
      "sudo ./aws/install",
      "./aws/install -i /usr/local/aws-cli -b /usr/local/bin",
      "aws --version",
      "aws configure set default.region us-east-1",
      "aws configure set aws_access_key_id ${var.aws_access_key}",
      "aws configure set aws_secret_access_key ${var.aws_secret_key}",
    ]
  }

  tags = {
    Name = "${var.tag}-worker${count.index + 1}"
  }
}

output "spot_instance_id" {
  value = aws_spot_instance_request.worker.*.spot_instance_id
}

output "spot_instance_public_ip" {
  value = aws_spot_instance_request.worker.*.public_ip
}

output "incoming_queue_url" {
  value = aws_sqs_queue.incoming-queue.id
}

output "outgoing_queue_url" {
  value = aws_sqs_queue.outgoing-queue.id
}

