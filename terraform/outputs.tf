output "aws_region" {
  value = var.aws_region
}

output "availability_zone" {
  value = var.availability_zone
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "vpc_cidr" {
  value = aws_vpc.main.cidr_block
}

output "public_subnet_id" {
  value = aws_subnet.public_bastion.id
}

output "private_sno_subnet_id" {
  value = aws_subnet.private_sno.id
}

output "private_hosted_zone_name" {
  value = aws_route53_zone.private.name
}

output "private_hosted_zone_id" {
  value = aws_route53_zone.private.zone_id
}

output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}

output "bastion_private_ip" {
  value = aws_instance.bastion.private_ip
}

output "bastion_ami_id" {
  value = aws_instance.bastion.ami
}

output "bastion_instance_type" {
  value = aws_instance.bastion.instance_type
}

output "install_config_snippet" {
  value = <<-EOT
baseDomain: ${aws_route53_zone.private.name}
metadata:
  name: sno415

publish: Internal

platform:
  aws:
    region: ${var.aws_region}
    subnets:
      - ${aws_subnet.private_sno.id}
    hostedZone: ${aws_route53_zone.private.zone_id}

networking:
  machineNetwork:
    - cidr: ${aws_vpc.main.cidr_block}
  EOT
}
