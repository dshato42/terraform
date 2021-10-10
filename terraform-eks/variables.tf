
variable "region" {
  type = string
  description = "the region to deploy the cluster"
}

variable "env_name" {
  type = string
  description = "The environment name"
}

variable "key_name" {
  type = string
  description = "the name of the ssh key to attachat to the worker nodes"
}