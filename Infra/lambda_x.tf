# Pakuje sadrzaj Twitter src/ foldera (handler.py + x_dataset.csv) u ZIP arhivu
data "archive_file" "x" {
  type = "zip"
  source_dir = "${path.module}/../Lambdas/Bronze/Twitter/src"
  output_path = "${path.module}/build/x.zip"
}

# X (Twitter) Lambda funkcija - ucitava staticki CSV dataset i upisuje ga sirov u S3;
# nema scheduler jer je dataset statican (pokrece se rucno, jednom)
resource "aws_lambda_function" "x" {
  function_name = "social-medias-x-bronze"
  role = aws_iam_role.x_lambda.arn        # rola koju funkcija preuzima
  handler = "handler.upload_twitter_dataset" # ulazna tacka: fajl.funkcija
  runtime = "python3.12"
  timeout = 60                               # kratko, samo upis jednog fajla
  memory_size = 256                              # manje memorije nego HN
  filename = data.archive_file.x.output_path
  source_code_hash = data.archive_file.x.output_base64sha256      # hash za detekciju izmena koda

  environment {
    variables = {
      X_BUCKET = aws_s3_bucket.data_lake.id     # ime bucketa kao env var
    }
  }
}