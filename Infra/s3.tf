# S3 bucket koji sluzi kao Data Lake - cuva sirove podatke u izvornom formatu bez transformacije
resource "aws_s3_bucket" "data_lake" {
  bucket = "social-medias-bigdata-2026"
  tags = {
    Project = "big-data"
    ManagedBy = "Terraform"
  }
}

# Block Public Access konfiguracija - eksplicitno onemogucava sve vidove javnog pristupa na nivou bucketa; primjena principa najmanjih privilegija
resource "aws_s3_bucket_public_access_block" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id   # referenca na ID bucketa
  block_public_acls = true  # odbija nove javne ACL-ove
  block_public_policy = true  # odbija bucket policy koje daju javni pristup
  ignore_public_acls = true   # ignoriše postojece javne ACL-ove
  restrict_public_buckets = true  # ogranicava pristup samo na autorizovane principale(Lambda role koje kroz IAM polise pisu u bucket)
}