# Pakuje sadrzaj HN src/ foldera (handler.py + zavisnosti) u ZIP arhivu
# koja se uploaduje kao kod Lambda funkcije
data "archive_file" "hn" {
  type = "zip"
  source_dir = "${path.module}/../Lambdas/Bronze/HN/src"
  output_path = "${path.module}/build/hn.zip"
}

# HN Lambda funkcija - prikuplja podatke sa Hacker News API-ja i upisuje sirov JSON u S3
resource "aws_lambda_function" "hn" {
  function_name = "social-medias-hn-bronze"
  role = aws_iam_role.hn_lambda.arn         # rola koju funkcija preuzima
  handler = "handler.fetch_hacker_news"     # ulazna tacka: fajl.funkcija
  runtime = "python3.12"
  timeout = 300                             # max 300s izvrsavanja
  memory_size = 512
  filename = data.archive_file.hn.output_path
  source_code_hash = data.archive_file.hn.output_base64sha256       # hash za detekciju izmena koda

  environment {
    variables = {
      HN_BUCKET = aws_s3_bucket.data_lake.id      # ime bucketa se prosledjuje kao env var
      HITS_PER_PAGE = "100"
    }
  }
}

# EventBridge Scheduler - okida HN Lambdu svaki dan u 00:00
resource "aws_scheduler_schedule" "hn_daily" {
  name = "social-medias-hn-daily"

  flexible_time_window {
    mode = "OFF"        # bez tolerancije, okida tacno u zakazano vreme
  }

  schedule_expression = "cron(0 0 * * ? *)"         # svaki dan u ponoc
  schedule_expression_timezone = "Europe/Belgrade"

  target {
    arn = aws_lambda_function.hn.arn                # koju funkciju okida
    role_arn = aws_iam_role.scheduler.arn           # pod kojom rolom
  }
}

# Trust policy - dozvoljava EventBridge Scheduler servisu da preuzme rolu
data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

# Rola koju Scheduler koristi za pozivanje Lambde
resource "aws_iam_role" "scheduler" {
  name = "social-medias-scheduler-role"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json
}

# Identity-based policy - dozvoljava pozivanje (invoke) iskljucivo HN Lambde; least privilege
data "aws_iam_policy_document" "scheduler_invoke" {
  statement {
    actions = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.hn.arn]    # samo HN Lambda, ne sve funkcije
  }
}

# Kacenje invoke policy na scheduler rolu
resource "aws_iam_role_policy" "scheduler_invoke" {
  name = "social-medias-scheduler-invoke"
  role = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler_invoke.json
}