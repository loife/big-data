variable "discord_webhook_url" {
  type      = string
  sensitive = true
}

resource "aws_sns_topic" "job_failures" {
  name = "social-medias-job-failures"
}

data "archive_file" "notifier" {
  type        = "zip"
  source_dir  = "${path.module}/../Lambdas/Notifier/src"
  output_path = "${path.module}/build/notifier.zip"
}

resource "aws_iam_role" "notifier_lambda" {
  name               = "social-medias-notifier-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy_attachment" "notifier_logs" {
  role       = aws_iam_role.notifier_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "notifier" {
  function_name    = "social-medias-notifier"
  role             = aws_iam_role.notifier_lambda.arn
  handler          = "handler.notify"
  runtime          = "python3.12"
  timeout          = 30
  filename         = data.archive_file.notifier.output_path
  source_code_hash = data.archive_file.notifier.output_base64sha256

  environment {
    variables = {
      DISCORD_WEBHOOK_URL = var.discord_webhook_url
    }
  }
}

resource "aws_lambda_permission" "notifier_from_sns" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notifier.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.job_failures.arn
}

resource "aws_sns_topic_subscription" "notifier" {
  topic_arn = aws_sns_topic.job_failures.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.notifier.arn
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = toset([
    "social-medias-hn-bronze",
    "social-medias-x-bronze",
    "social-medias-silver",
    "social-medias-gold",
    "social-medias-loader",
  ])

  alarm_name          = "${each.value}-errors"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = each.value
  }

  alarm_actions = [aws_sns_topic.job_failures.arn]
}