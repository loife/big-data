import json
import os
from datetime import datetime, timezone, timedelta

import boto3
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

from concurrent.futures import ThreadPoolExecutor, as_completed

ALGOLIA_BASE_URL = "https://hn.algolia.com/api/v1"
ALGOLIA_PAGE_WORKERS = 10
HN_USER_WORKERS = 20

s3 = boto3.client("s3")


def create_http_session():
    retry = Retry(
        total=5,
        connect=5,
        read=5,
        status=5,
        backoff_factor=1,
        status_forcelist=(413, 429, 500, 502, 503, 504),
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

def fetch_user(username):
    response = http.get(
        f"https://hacker-news.firebaseio.com/v0/user/{username}.json",
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
            "users": left_result["users"] | right_result["users"],
            "objects": left_result["objects"] + right_result["objects"],
        }

    total_pages = int(first_page.get("nbPages", 0))
    written_objects = []
    hit_count_written = 0

    users = set()
    pages = [first_page]
    with ThreadPoolExecutor(max_workers=ALGOLIA_PAGE_WORKERS) as executor:
        future_to_page = {
            executor.submit(fetch_algolia_page, start_ts, end_ts, page_number): page_number
            for page_number in range(1, total_pages)
        }

        for future in as_completed(future_to_page):
            pages.append(future.result())


    for page_number, page_response in enumerate(pages):
        hits = page_response.get("hits") or []
        for hit in hits:
            users.add(hit.get("author"))

        object_key = (
            f"{prefix}"
            f"window_start_ts={start_ts}/"
            f"window_end_ts={end_ts}/"
            f"page={page_number}.json"
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
        "users": users,
        "objects": written_objects,
    }

def fetch_and_store_users(bucket_name, prefix, users):
    if None in users:
        users.remove(None)
    fetched_users = []
    with ThreadPoolExecutor(max_workers=HN_USER_WORKERS) as executor:
        future_to_page = {
            executor.submit(fetch_user, username): username
            for username in users
        }

        for future in as_completed(future_to_page):
            username = future_to_page[future]

            try:
                user = future.result()

                if user is not None:
                    fetched_users.append(user)

            except Exception as exc:
                print(f"Failed to fetch user {username}: {exc}")

    for user in fetched_users:
        username = user.get("id")
        if not username: continue

        object_key = (f"{prefix}{username}.json")

        put_json(
            bucket_name=bucket_name,
            key=object_key,
            value=user,
        )

def fetch_hacker_news(event, context):
    bucket_name = os.environ["HN_BUCKET"]

    now = datetime.now(timezone.utc)
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)
    yesterday_start = today_start - timedelta(days=1)

    start_ts = int(yesterday_start.timestamp())
    end_ts = int(today_start.timestamp())

    run_ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H-%M-%SZ")

    posts_prefix = f"hacker-news/raw/run_ts={run_ts}/"
    users_prefix = f"hacker-news/users/run_ts={run_ts}/"
    manifest_prefix = f"hacker-news/manifests/run_ts={run_ts}/"

    print("Fetching Hacker News data")
    print(f"Timestamp window: {start_ts} <= created_at_i < {end_ts}")
    print(f"Posts prefix: {posts_prefix}")
    print(f"Users prefix: {users_prefix}")


    result = fetch_and_store_all_between(
        bucket_name=bucket_name,
        prefix=posts_prefix,
        start_ts=start_ts,
        end_ts=end_ts,
    )

    fetch_and_store_users(
        bucket_name=bucket_name,
        prefix=users_prefix,
        users=result["users"]
    )
    manifest = {
        "status": "success",
        "bucket": bucket_name,
        "posts_prefix": posts_prefix,
        "users_prefix": users_prefix,
        "users_count": len(result["users"]),
        "page_count": result["page_count"],
        "hit_count_written": result["hit_count_written"],
    }

    put_json(
        bucket_name=bucket_name,
        key=f"{manifest_prefix}manifest.json",
        value=manifest,
    )

    print("Export complete")
    
    return manifest