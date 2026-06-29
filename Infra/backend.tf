# =====================================================================
#  REMOTE STATE - deljeni Terraform state na S3
#  Ceo tim koristi ISTI state fajl, pa nema vise "already exists" konflikata.
#  NAPOMENA: backend ne sme da koristi varijable - vrednosti su hardkodovane.
#  S3 bucket za state mora postojati PRE 'terraform init' (vidi UPUTSTVO sekciju 10).
# =====================================================================
terraform {
  backend "s3" {
    bucket       = "social-medias-tfstate-669707689294"
    key          = "big-data/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true # zakljucavanje state-a (Terraform >= 1.10) - sprecava da dvoje istovremeno menjaju
  }
}
