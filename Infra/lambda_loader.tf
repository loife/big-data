# ECR repo za container image loader lambde
resource "aws_ecr_repository" "loader" {
  name                 = "social-medias-loader"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

#IAM role za loader lambdu
resource "aws_iam_role" "loader_lambda" {
  name = "social-medias-loader-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# least privilege - loader sme samo da cita gold bucket
resource "aws_iam_role_policy" "loader_lambda" {
  name = "social-medias-loader-policy"
  role = aws_iam_role.loader_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadGold"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = [
          aws_s3_bucket.gold_data_lake.arn,
          "${aws_s3_bucket.gold_data_lake.arn}/*",
        ]
      },
    ]
  })
}

# dozvola za rad u VPCu
resource "aws_iam_role_policy_attachment" "loader_vpc" {
  role       = aws_iam_role.loader_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

#lambda funkcija
resource "aws_lambda_function" "loader" {
  function_name = "social-medias-loader"
  role          = aws_iam_role.loader_lambda.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.loader.repository_url}:latest"

  timeout     = 300
  memory_size = 1024

  # lambda u privatnom subnetu sa lambda SG
  vpc_config {
    subnet_ids         = [aws_subnet.private.id]
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      GOLD_BUCKET = aws_s3_bucket.gold_data_lake.id
      PG_HOST     = aws_instance.viz.private_ip # privatna IP EC2 instance unutar VPC-a
      PG_PORT     = "5432"
      PG_DB       = "metrics"
      PG_USER     = var.db_user
      PG_PASSWORD = var.db_password
    }
  }
}

# raspored - loader svaki dan u 07:00
resource "aws_cloudwatch_event_rule" "loader_daily" {
  name                = "social-medias-loader-daily"
  schedule_expression = "cron(0 7 * * ? *)"
}

resource "aws_cloudwatch_event_target" "loader_daily" {
  rule = aws_cloudwatch_event_rule.loader_daily.name
  arn  = aws_lambda_function.loader.arn
}

resource "aws_lambda_permission" "invoke_loader" {
  statement_id  = "AllowLoaderScheduledInvocation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.loader.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.loader_daily.arn
}
