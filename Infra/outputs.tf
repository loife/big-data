# Ispisuje ime kreiranog bucketa nakon terraform apply
output "bucket_name" {
  value = aws_s3_bucket.data_lake.id
}