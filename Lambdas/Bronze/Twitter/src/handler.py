import os
from datetime import datetime, timezone

import boto3

s3 = boto3.client("s3")


def upload_twitter_dataset(event, context):
    bucket_name = os.environ["X_BUCKET"]

    run_ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H-%M-%SZ")
    key = f"x/raw/run_ts={run_ts}/x_dataset.csv"

    current_dir = os.path.dirname(os.path.abspath(__file__))
    csv_path = os.path.join(current_dir, "x_dataset.csv")

    with open(csv_path, "rb") as csv_file:
        s3.put_object(
            Bucket=bucket_name,
            Key=key,
            Body=csv_file.read(),
            ContentType="text/csv",
        )

    return {
        "status": "success",
        "bucket": bucket_name,
        "key": key,
        "source_file": "x_dataset.csv"
    }