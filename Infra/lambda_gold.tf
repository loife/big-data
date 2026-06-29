locals {
  silver_bucket_name = "social-medias-silver-bigdata-2026"
}

resource "aws_ecr_repository" "gold" {
  name                 = "social-medias-gold"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

resource "aws_s3_bucket" "gold_data_lake" {
  bucket = "social-medias-gold-bigdata-2026"
}

resource "aws_s3_bucket_public_access_block" "gold_data_lake" {
  bucket = aws_s3_bucket.gold_data_lake.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_role" "gold_lambda" {
  name = "social-medias-gold-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "gold_lambda" {
  name = "social-medias-gold-policy"
  role = aws_iam_role.gold_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadSilver"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::${local.silver_bucket_name}",
          "arn:aws:s3:::${local.silver_bucket_name}/*",
        ]
      },
      {
        Sid    = "WriteGold"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.gold_data_lake.arn,
          "${aws_s3_bucket.gold_data_lake.arn}/*",
        ]
      },
      {
        Sid      = "Logs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
    ]
  })
}

resource "aws_lambda_function" "gold" {
  function_name = "social-medias-gold"
  role          = aws_iam_role.gold_lambda.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.gold.repository_url}:latest"

  timeout     = 300
  memory_size = 1024

  environment {
    variables = {
      SILVER_BUCKET = local.silver_bucket_name
      GOLD_BUCKET   = aws_s3_bucket.gold_data_lake.id
    }
  }
}

resource "aws_cloudwatch_event_rule" "gold_daily" {
  name                = "social-medias-gold-daily"
  schedule_expression = "cron(0 6 * * ? *)"
}

resource "aws_cloudwatch_event_target" "gold_daily" {
  rule = aws_cloudwatch_event_rule.gold_daily.name
  arn  = aws_lambda_function.gold.arn
}

resource "aws_lambda_permission" "invoke_gold" {
  statement_id  = "AllowGoldScheduledInvocation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.gold.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.gold_daily.arn
}