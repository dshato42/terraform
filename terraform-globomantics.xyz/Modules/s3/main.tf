
resource "aws_iam_role" "allow_instance_s3" {
  name = "${var.name}_allow_instance_s3"

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
      },
    ]
  })
}

resource "aws_iam_instance_profile" "instance_profile" {
  name = "${var.name}_instance_profile"
  role = aws_iam_role.allow_instance_s3.name
}

# grant premisions all to the allow nginx s3 role
# the s3 that was created and its content
resource "aws_iam_role_policy" "allow_s3_all" {
  name = "${var.name}_allow_s3_all"
  role = aws_iam_role.allow_instance_s3.name

  policy = jsonencode(
    {
      Version = "2012-10-17",
      Statement = [
        {
          Action = [
            "s3:*"
          ]
          Effect = "Allow"
          Resource = [
            "arn:aws:s3:::${var.name}",
            "arn:aws:s3:::${var.name}/*"
          ]
        }
      ]
  })

}

# create s3 bucket
resource "aws_s3_bucket" "web_bucket" {
  bucket        = var.name
  acl           = "private"
  force_destroy = true

  tags = merge(var.common_tags, { Name = "${var.name}-web-bucket" })
}