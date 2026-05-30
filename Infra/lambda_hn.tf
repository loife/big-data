data "archive_file" "hn" {
  type = "zip"
  source_dir = "${path.module}/../Lambdas/Bronze/HN/src"
  output_path = "${path.module}/build/hn.zip"
}

resource "aws_lambda_function" "hn" {
  function_name = "social-medias-hn-bronze"
  role = aws_iam_role.hn_lambda.arn
  handler = "handler.fetch_hacker_news"
  runtime = "python3.12"
  timeout = 300
  memory_size = 512
  filename = data.archive_file.hn.output_path
  source_code_hash = data.archive_file.hn.output_base64sha256

  environment {
    variables = {
      HN_BUCKET = aws_s3_bucket.data_lake.id
      HITS_PER_PAGE = "100"
    }
  }
}

resource "aws_scheduler_schedule" "hn_daily" {
  name = "social-medias-hn-daily"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = "cron(0 0 * * ? *)"
  schedule_expression_timezone = "Europe/Belgrade"

  target {
    arn = aws_lambda_function.hn.arn
    role_arn = aws_iam_role.scheduler.arn
  }
}

data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name = "social-medias-scheduler-role"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json
}

data "aws_iam_policy_document" "scheduler_invoke" {
  statement {
    actions = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.hn.arn]
  }
}

resource "aws_iam_role_policy" "scheduler_invoke" {
  name = "social-medias-scheduler-invoke"
  role = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler_invoke.json
}