import json
import os
from time import time
from datetime import datetime, timezone

import boto3
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry


ALGOLIA_BASE_URL = "https://hn.algolia.com/api/v1"

s3 = boto3.client("s3")


def create_http_session():
    retry = Retry(
        total=5,
        connect=5,
        read=5,
        status=5,
        backoff_factor=1,
        status_forcelist=(429, 500, 502, 503, 504),
        allowed_methods=("GET",),
        respect_retry_after_header=True,
    )

    adapter = HTTPAdapter(max_retries=retry)

    session = requests.Session()
    session.mount("https://", adapter)
    session.mount("http://", adapter)

    return session


http = create_http_session()


def fetch_algolia_page(start_ts, end_ts, page):
    hits_per_page = int(os.environ.get("HITS_PER_PAGE", "100"))

    response = http.get(
        f"{ALGOLIA_BASE_URL}/search_by_date",
        params={
            "tags": "(poll,job,ask_hn,story,comment)",
            "numericFilters": f"created_at_i>={start_ts},created_at_i<{end_ts}",
            "page": page,
            "hitsPerPage": hits_per_page,
        },
        timeout=20,
    )

    response.raise_for_status()
    return response.json()


def put_json(bucket_name, key, value):
    s3.put_object(
        Bucket=bucket_name,
        Key=key,
        Body=json.dumps(value, ensure_ascii=False, indent=2).encode("utf-8"),
        ContentType="application/json",
    )


def make_page_key(prefix, window_start_ts, window_end_ts, page_number):
    return (
        f"{prefix}/"
        f"window_start_ts={window_start_ts}/"
        f"window_end_ts={window_end_ts}/"
        f"page={page_number}.json"
    )


def fetch_and_store_all_between(bucket_name, prefix, start_ts, end_ts):
    first_page = fetch_algolia_page(
        start_ts=start_ts,
        end_ts=end_ts,
        page=0,
    )

    nb_hits = int(first_page.get("nbHits", 0))

    if nb_hits > 1000:
        mid_ts = (start_ts + end_ts) // 2

        if mid_ts == start_ts or mid_ts == end_ts:
            raise RuntimeError(
                f"Can't split window further: {start_ts} to {end_ts}, "
                f"but nbHits={nb_hits}"
            )

        left_result = fetch_and_store_all_between(
            bucket_name=bucket_name,
            prefix=prefix,
            start_ts=start_ts,
            end_ts=mid_ts,
        )

        right_result = fetch_and_store_all_between(
            bucket_name=bucket_name,
            prefix=prefix,
            start_ts=mid_ts,
            end_ts=end_ts,
        )

        return {
            "start_ts": start_ts,
            "end_ts": end_ts,
            "was_split": True,
            "nb_hits_reported": nb_hits,
            "page_count": left_result["page_count"] + right_result["page_count"],
            "hit_count_written": left_result["hit_count_written"] + right_result["hit_count_written"],
            "objects": left_result["objects"] + right_result["objects"],
        }

    total_pages = int(first_page.get("nbPages", 0))
    written_objects = []
    hit_count_written = 0

    for page_number in range(total_pages):
        if page_number == 0:
            page_response = first_page
        else:
            page_response = fetch_algolia_page(
                start_ts=start_ts,
                end_ts=end_ts,
                page=page_number,
            )

        object_key = make_page_key(
            prefix=prefix,
            window_start_ts=start_ts,
            window_end_ts=end_ts,
            page_number=page_number,
        )

        put_json(
            bucket_name=bucket_name,
            key=object_key,
            value=page_response,
        )

        written_objects.append(object_key)
        hit_count_written += len(page_response.get("hits", []))

    return {
        "start_ts": start_ts,
        "end_ts": end_ts,
        "was_split": False,
        "nb_hits_reported": nb_hits,
        "page_count": total_pages,
        "hit_count_written": hit_count_written,
        "objects": written_objects,
    }


def fetch_hacker_news(event, context):
    bucket_name = os.environ["HN_BUCKET"]

    end_ts = int(time())
    start_ts = end_ts - 86400  # 84600 seconds in a day

    run_ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H-%M-%SZ")

    prefix = (
        f"hacker-news/raw/"
        f"run_ts={run_ts}/"
    )

    print("Fetching Hacker News data")
    print(f"Timestamp window: {start_ts} <= created_at_i < {end_ts}")
    print(f"S3 prefix: {prefix}")

    result = fetch_and_store_all_between(
        bucket_name=bucket_name,
        prefix=prefix,
        start_ts=start_ts,
        end_ts=end_ts,
    )

    print("Export complete")

    return {
        "status": "success",
        "bucket": bucket_name,
        "prefix": prefix,
        "page_count": result["page_count"],
        "hit_count_written": result["hit_count_written"],
    }