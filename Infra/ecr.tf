resource "aws_ecr_repository" "silver" {
  name = "social-medias-silver-ecr"
  image_tag_mutability = "MUTABLE" 
  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "silver" {
  repository = aws_ecr_repository.silver.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 5 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 5
      }
      action = { type = "expire" }
    }]
  })
}