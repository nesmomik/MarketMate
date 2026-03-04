# output variables for testing
output "alb_dns_name" {
  value = aws_lb.load_balancer.dns_name
}

output "docker_host_1_private_ip" {
  value = aws_instance.docker_host_1.private_ip
}

output "docker_host_2_private_ip" {
  value = aws_instance.docker_host_2.private_ip
}

output "nat_instance_public_ip" {
  value = aws_instance.nat_instance.public_ip
}
