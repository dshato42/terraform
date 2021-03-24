
##################################################################################
# PROVIDERS
##################################################################################

provider "aws" {
  profile = "default"
  region     = var.region
}

provider "azurerm" {
  subscription_id = var.arm_subscription_id
  client_id       = var.arm_principal
  client_secret   = var.arm_password
  tenant_id       = var.tenant_id
  alias           = "arm-1"
  #Added when using service principal with limited permissions
  skip_provider_registration = true

  #Required for version 2.0 of provider
  features {}
}


##################################################################################
# DATA
##################################################################################

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

data "aws_availability_zones" "available" {}

data "template_file" "public_cidrsubnet" {
  count = var.subnet_count[terraform.workspace]
  template = "$${cidrsubnet(vpc_cidr,8,current_count)}"

  vars = {
    vpc_cidr =  var.network_address_space[terraform.workspace]
    current_count = count.index
  }
}


##################################################################################
# RESOURCES
##################################################################################

resource "random_integer" "rand" {
  min = 10000
  max = 99999
}

# NETWORKING #

module "vpc" {
    source = "terraform-aws-modules/vpc/aws"
    name = "${local.env_name}-vpc"
    version = "2.15.0"

    cidr = var.network_address_space[terraform.workspace]
    azs = slice(data.aws_availability_zones.available.names, 0 ,var.subnet_count[terraform.workspace])
    public_subnets = data.template_file.public_cidrsubnet[*].rendered
    private_subnets = []

    tags = local.common_tags
    
}

resource "aws_security_group" "elb-sg" {
  name   = "nginx_elb_sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    description = "allow Inbound http access to all via port 80"
    from_port   = 80
    protocol    = "tcp"
    to_port     = 80
  }
  #allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# create sg for allowd ssh and http inbound
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
    cidr_blocks = [var.network_address_space[terraform.workspace]]
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

module "bucket" {
  source = "./Modules/s3"
  name = local.s3_bucket_name
  common_tags = local.common_tags

}

# upload index.html to s3 bucket
resource "aws_s3_bucket_object" "website" {
  bucket = module.bucket.bucket.id
  key    = "/website/index.html"
  source = "./index.html"
}

# upload png to s3 bucket
resource "aws_s3_bucket_object" "graphic" {
  bucket = module.bucket.bucket.id
  key    = "/website/Globo_logo_Vert.png"
  source = "./Globo_logo_Vert.png"
}



# INSTANCES
# creating s3 config file.
# file provisioner don't have sudo
resource "aws_instance" "nginx" {
  count                  = var.instance_count[terraform.workspace]
  ami                    = data.aws_ami.aws-linux.id
  instance_type          = var.instance_size[terraform.workspace]
  subnet_id              = module.vpc.public_subnets[count.index % var.subnet_count[terraform.workspace]]
  vpc_security_group_ids = [aws_security_group.nginx-sg.id]
  key_name               = var.key_name
  iam_instance_profile   = module.bucket.instance_profile.name
  depends_on = [module.bucket]

  connection {
    type        = "ssh"
    host        = self.public_ip
    user        = "ec2-user"
    private_key = file(var.private_key_path)

  }

  provisioner "file" {
    content = <<EOF
    access_key = 
    security_key = 
    security_token = 
    use_https = True
    bucket_location = US
    EOF

    destination = "/home/ec2-user/.s3cfg"
  }

  # create nginx logrotate file
  provisioner "file" {
    content     = <<EOF
    /var/log/nginx/*log {
        daily
        rotate 10
        missingok
        compress
        sharedscripts
        postrotate
        endscript
        lastaction
            INSTANCE_ID=`curl --silent http://169.254.169.254/latest/meta-data/instance-id`
            sudo /usr/local/bin/s3cmd sync --config=/home/ec2-user/.s3cfg /var/log/nginx/ s3://${module.bucket.bucket.id}/nginx/$INSTANCE_ID/
        endscript
    }

    EOF
    destination = "/home/ec2-user/nginx"
  }
  # provisioner steps:
  # 1. download and start nginx service.
  # 2. copy s3 config file to the root user
  # 3. copy the nginx logrotate file to the logrotate.d folder
  # 4. download s3cmd
  # 5. get the index.html file and the Globo_log_Vert.png file from s3 bucket.
  # 6. copy mentioned above files to the nginx html folder to make them ready to be seved.
  # 7. forcing log rotate to create the logs that we would be able to se feedback.
  provisioner "remote-exec" {
    inline = [
      "sudo yum install nginx -y",
      "sudo service nginx start",
      "sudo cp /home/ec2-user/.s3cfg /root/.s3cfg",
      "sudo cp /home/ec2-user/nginx /etc/logrotate.d/nginx",
      "sudo pip install s3cmd",
      "s3cmd get s3://${module.bucket.bucket.id}/website/index.html .",
      "s3cmd get s3://${module.bucket.bucket.id}/website/Globo_logo_Vert.png .",
      "sudo rm /usr/share/nginx/html/index.html",
      "sudo cp /home/ec2-user/index.html /usr/share/nginx/html/index.html",
      "sudo cp /home/ec2-user/Globo_logo_Vert.png /usr/share/nginx/html/Globo_logo_Vert.png",
      "sudo logrotate -f /etc/logrotate.conf"
    ]
  }
  tags = merge(local.common_tags, { Name = "${local.env_name}-nginx${count.index + 1}" })

}


resource "aws_elb" "web" {
  name            = "nginx-elb"
  instances       = aws_instance.nginx[*].id
  subnets         = module.vpc.public_subnets
  security_groups = [aws_security_group.elb-sg.id]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  tags = merge(local.common_tags, { Name = "${local.env_name}-elb" })
}


resource "azurerm_dns_cname_record" "elb" {

  name                = "${local.env_name}-website"
  zone_name           = var.dns_zone_name
  resource_group_name = var.dns_resource_group
  ttl                 = 30
  record              = aws_elb.web.dns_name
  provider            = azurerm.arm-1

  tags = merge(local.common_tags, { Name = "${local.env_name}-website" })

}
