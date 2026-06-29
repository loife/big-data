resource "aws_lambda_function" "silver" {
  function_name = "social-medias-silver"
  role          = aws_iam_role.silver_lambda.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.silver.repository_url}:latest"

  timeout     = 300
  memory_size = 1024

  # f-ja radi unutar privatnog subneta
  vpc_config {
    subnet_ids         = [aws_subnet.private.id]
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      SILVER_BUCKET = aws_s3_bucket.silver_data_lake.id
    }
  }
}

# dozvola za rad u VPCu
resource "aws_iam_role_policy_attachment" "silver_vpc" {
  role       = aws_iam_role.silver_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_lambda_permission" "invoke_silver" {
  statement_id  = "AllowSilverInvocation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.silver.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.data_lake.arn
}

resource "aws_s3_bucket_notification" "bronze_to_silver" {
  bucket = aws_s3_bucket.data_lake.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.silver.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "hacker-news/raw/"
    filter_suffix       = ".json"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.silver.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "hacker-news/manifests/"
    filter_suffix       = ".json"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.silver.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "x/raw/"
    filter_suffix       = ".csv"
  }

  depends_on = [
    aws_lambda_permission.invoke_silver
  ]
}