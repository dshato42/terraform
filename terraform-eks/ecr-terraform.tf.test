
variable "ecr_repository_name" {
  type        = string
  description = "the name of the ecr repository"
}

variable "region" {
  type        = string
  description = "the name of the region"
}

provider "aws" {
  profile = "default"
  region  = var.region
}


resource "aws_ecr_repository" "ecr-repo" {
  name                 = var.ecr_repository_name
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    "Name" = "aws_ecr-sela"
  }
}

output "aws_ecr_registry_uri" {
  value = aws_ecr_repository.ecr-repo.repository_url
}

