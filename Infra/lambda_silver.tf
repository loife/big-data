resource "aws_lambda_function" "silver" {
    function_name = "social-medias-silver"
    role = aws_iam_role.silver_lambda.arn
    handler = "handler.normalize_bronze"
    runtime = "python3.12"

    timeout = 300
    memory_size = 1024

    filename = data.archive_file.social_media_silver.output_path
    source_code_hash = data.archive_file.social_media_silver.output_base64sha256

    environment {
        variables = {
            SILVER_BUCKET = aws_s3_bucket.silver_data_lake.id
        }
    }
}

resource "aws_lambda_permission" "invoke_silver" {
    statement_id = "AllowSilverInvocation"
    action = "lambda:InvokeFunction"
    function_name = aws_lambda_function.social_media_silver.function_name
    principal = "s3.amazonaws.com"
    source_arn = aws_s3_bucket.data_lake.arn
}

resource "aws_s3_bucket_notification" "bronze_to_silver" {
  bucket = aws_s3_bucket.data_lake.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.social_media_silver.arn
    events = ["s3:ObjectCreated:*"]
    filter_prefix = "hacker-news/raw/"
    filter_suffix = ".json"
  }

  lambda_function {
    lambda_function_arn = aws_lambda_function.social_media_silver.arn
    events = ["s3:ObjectCreated:*"]
    filter_prefix = "x/raw/"
    filter_suffix = ".csv"
  }

  depends_on = [
    aws_lambda_permission.allow_bronze_s3_to_invoke_silver
  ]
}