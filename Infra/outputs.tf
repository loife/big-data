# Ispisuje ime kreiranog bucketa nakon terraform apply
output "bucket_name" {
  value = aws_s3_bucket.data_lake.id
}

output "vpc_id" {
  value       = aws_vpc.main.id
}

output "superset_url" {
  description = "login: admin"
  value       = "http://${aws_instance.viz.public_ip}:8088"
}

output "ec2_public_ip" {
  value       = aws_instance.viz.public_ip
}

output "ec2_private_ip" {
  value       = aws_instance.viz.private_ip
}

output "loader_ecr_url" {
  value       = aws_ecr_repository.loader.repository_url
}