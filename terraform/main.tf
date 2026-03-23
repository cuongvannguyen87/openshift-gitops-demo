terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name    = "ocp-sno-vpc"
    Project = var.project_tag
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name    = "ocp-sno-igw"
    Project = var.project_tag
  }
}

resource "aws_subnet" "public_bastion" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name    = "ocp-sno-public-bastion"
    Project = var.project_tag
  }
}

resource "aws_subnet" "private_sno" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_sno_subnet_cidr
  availability_zone       = var.availability_zone
  map_public_ip_on_launch = false

  tags = {
    Name    = "ocp-sno-private-sno"
    Project = var.project_tag
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name    = "ocp-sno-nat-eip"
    Project = var.project_tag
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_bastion.id

  tags = {
    Name    = "ocp-sno-nat"
    Project = var.project_tag
  }

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name    = "ocp-sno-public-rt"
    Project = var.project_tag
  }
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_bastion.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name    = "ocp-sno-private-rt"
    Project = var.project_tag
  }
}

resource "aws_route" "private_default" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

resource "aws_route_table_association" "private_assoc" {
  subnet_id      = aws_subnet.private_sno.id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "bastion" {
  name        = "ocp-sno-bastion-sg"
  description = "Allow SSH to bastion"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from admin"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "ocp-sno-bastion-sg"
    Project = var.project_tag
  }
}

resource "aws_route53_zone" "private" {
  name = var.private_hosted_zone_name

  vpc {
    vpc_id = aws_vpc.main.id
  }

  tags = {
    Name    = "ocp-sno-private-zone"
    Project = var.project_tag
  }
}

resource "aws_key_pair" "bastion" {
  key_name   = "ocp-sno-bastion-key"
  public_key = var.bastion_ssh_public_key

  tags = {
    Name    = "ocp-sno-bastion-key"
    Project = var.project_tag
  }
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.bastion_instance_type
  subnet_id                   = aws_subnet.public_bastion.id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.bastion.key_name

  tags = {
    Name    = "ocp-sno-bastion"
    Project = var.project_tag
  }
}
