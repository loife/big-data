# Trust policy (KO smije da preuzme rolu) - dijeljena izmedju obje Lambda role;
# dozvoljava Lambda servisu da preuzme rolu putem sts:AssumeRole
data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type = "Service"
      identifiers = ["lambda.amazonaws.com"]  # principal je Lambda servis
    }
  }
}

# IAM rola koju preuzima HN Lambda tokom izvrsavanja
resource "aws_iam_role" "hn_lambda" {
  name = "social-medias-hn-bronze-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json  # KO
}

# Identity-based policy (STA rola smije da radi) - HN Lambda smije samo PutObject
# i to iskljucivo u hacker-news/ prefiks bucketa; primjena least privilege
data "aws_iam_policy_document" "hn_s3" {
  statement {
    actions = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.data_lake.arn}/hacker-news/*"]  # samo svoj prefiks
  }
}

# Kacenje identity-based policy na HN rolu (inline policy)
resource "aws_iam_role_policy" "hn_s3" {
  name = "social-medias-hn-s3"
  role = aws_iam_role.hn_lambda.id
  policy = data.aws_iam_policy_document.hn_s3.json   # STA
}

# Predefinisana AWS managed policy - daje HN Lambdi pravo pisanja logova u CloudWatch
resource "aws_iam_role_policy_attachment" "hn_logs" {
  role = aws_iam_role.hn_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# IAM rola koju preuzima X (Twitter) Lambda; koristi istu trust policy kao HN
resource "aws_iam_role" "x_lambda" {
  name = "social-medias-x-bronze-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json  # KO
}

# Identity-based policy za X Lambdu - PutObject iskljucivo u x/ prefiks
data "aws_iam_policy_document" "x_s3" {
  statement {
    actions = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.data_lake.arn}/x/*"]   # samo svoj prefiks
  }
}

# Kacenje identity-based policy na X rolu
resource "aws_iam_role_policy" "x_s3" {
  name   = "social-medias-x-s3"
  role   = aws_iam_role.x_lambda.id
  policy = data.aws_iam_policy_document.x_s3.json
}

# Predefinisana AWS managed policy - logovi u CloudWatch za X Lambdu
resource "aws_iam_role_policy_attachment" "x_logs" {
  role       = aws_iam_role.x_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}