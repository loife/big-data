data "archive_file" "x" {
  type        = "zip"
  source_dir  = "${path.module}/../Lambdas/Bronze/Twitter/src"
  output_path = "${path.module}/build/x.zip"
}

resource "aws_lambda_function" "x" {
  function_name    = "social-medias-x-bronze"
  role             = aws_iam_role.x_lambda.arn
  handler          = "handler.upload_twitter_dataset"
  runtime          = "python3.12"
  timeout          = 60
  memory_size      = 256
  filename         = data.archive_file.x.output_path
  source_code_hash = data.archive_file.x.output_base64sha256

  environment {
    variables = {
      X_BUCKET = aws_s3_bucket.data_lake.id
    }
  }
}