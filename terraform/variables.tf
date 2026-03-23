variable "aws_region" {
  type    = string
  default = "ap-southeast-1"
}

variable "availability_zone" {
  type    = string
  default = "ap-southeast-1a"
}

variable "vpc_cidr" {
  type    = string
  default = "10.10.0.0/16"
}

variable "public_subnet_cidr" {
  type    = string
  default = "10.10.1.0/24"
}

variable "private_sno_subnet_cidr" {
  type    = string
  default = "10.10.10.0/24"
}

variable "private_hosted_zone_name" {
  type    = string
  default = "aws.ocp.internal"
}

variable "admin_cidr" {
  type = string
}

variable "bastion_ssh_public_key" {
  type      = string
  sensitive = true
}

variable "bastion_instance_type" {
  type    = string
  default = "t3.small"
}

variable "project_tag" {
  type    = string
  default = "default-project-tag"
}
