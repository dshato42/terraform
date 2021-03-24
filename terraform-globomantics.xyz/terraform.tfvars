
key_name         = "my_ssh_key"
private_key_path = "/vagrant/my_ssh_key.pem"
billing_code_tag = "ACCT8675309"
environment_tag = "dev"
bucket_name_prefix = "globo"

# You will need to create a service principal
# Check the README for instructions
arm_subscription_id = ""

# This will be the appId from the service principal creation
arm_principal = ""

arm_password = ""

tenant_id = ""

dns_zone_name = "globomantics.xyz"

dns_resource_group = "dns"

network_address_space = {
  Development = "10.0.0.0/16"
  UAT = "10.1.0.0/16"
  Production = "10.2.0.0/16"
}

instance_size = {
  Development = "t2.micro"
  UAT = "t2.small"
  Production = "t2.medium"
}

subnet_count = {
  Development = 2
  UAT = 2
  Production = 3
}

instance_count = {
  Development = 2
  UAT = 4
  Production = 6
}
