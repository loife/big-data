data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "hn_lambda" {
  name = "social-medias-hn-bronze-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "hn_s3" {
  statement {
    actions = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.data_lake.arn}/hacker-news/*"]
  }
}

resource "aws_iam_role_policy" "hn_s3" {
  name = "social-medias-hn-s3"
  role = aws_iam_role.hn_lambda.id
  policy = data.aws_iam_policy_document.hn_s3.json
}

resource "aws_iam_role_policy_attachment" "hn_logs" {
  role = aws_iam_role.hn_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}