import csv
import io
import json
import os
import pandas as pd
from datetime import datetime, timezone
import hashlib
import re
import awswrangler as wr
from urllib.parse import unquote_plus

import boto3

s3 = boto3.client("s3")

BRONZE_PREFIX_HN_POST = "hacker-news/raw/"
BRONZE_PREFIX_HN_USER = "hacker-news/users/"
BRONZE_PREFIX_HN_MANIFEST = "hacker-news/manifests/"
BRONZE_PREFIX_X = "x/raw/"

CLEANR = re.compile('<.*?>') 

def read_s3_object(bucket_name, key):
    response = s3.get_object(Bucket=bucket_name, Key=key)
    return response["Body"].read()


def normalize_bronze(event, context):
    results = []

    for record in event.get("Records", []):
        source_bucket = record["s3"]["bucket"]["name"]
        bronze_key = unquote_plus(record["s3"]["object"]["key"])

        result = process_object(source_bucket, bronze_key)
        results.append(result)

    return {
        "status": "success",
        "results": results,
    }

def process_object(source_bucket, bronze_key):
    silver_bucket = os.environ["SILVER_BUCKET"]

    if bronze_key.startswith(BRONZE_PREFIX_HN_MANIFEST):
        users_df, posts_df, post_children_df = process_hn_manifest(source_bucket, bronze_key)

    elif bronze_key.startswith(BRONZE_PREFIX_HN_POST):
        users_df, posts_df, post_children_df = normalize_hn_post(source_bucket, bronze_key)

    elif bronze_key.startswith(BRONZE_PREFIX_X):
        users_df, posts_df, post_children_df = normalize_x_file(source_bucket,bronze_key)
    
    elif bronze_key.startswith(BRONZE_PREFIX_HN_USER):
        return {
            "status": "skipped",
            "source_bucket": source_bucket,
            "source_key": bronze_key,
        }

    else:
        print(f"Could not read object type: s3://{source_bucket}/{bronze_key}")

        return {
            "status": "skipped",
            "source_bucket": source_bucket,
            "source_key": bronze_key,
        }
       
    if not users_df.empty:
        users_df = users_df.drop_duplicates(subset=["id"])

        wr.s3.to_parquet(
            df=users_df,
            path=f"s3://{silver_bucket}/users/",
            dataset=True,
            mode="append",
            partition_cols=["platform"],
        )

    if not posts_df.empty:
        posts_df["date"] = pd.to_datetime(
            posts_df["created_at"],
            utc=True,
            errors="coerce",
        ).dt.strftime("%Y-%m-%d")

        posts_df = posts_df.drop_duplicates(subset=["id"])

        wr.s3.to_parquet(
            df=posts_df,
            path=f"s3://{silver_bucket}/posts/",
            dataset=True,
            mode="append",
            partition_cols=["date"],
        )

    if not post_children_df.empty:
        post_children_df = post_children_df.drop_duplicates(
            subset=["parent_id", "child_id"]
        )

        wr.s3.to_parquet(
            df=post_children_df,
            path=f"s3://{silver_bucket}/post_children/",
            dataset=True,
            mode="append",
            partition_cols=["platform"],
        )

    return {
        "status": "success",
        "source_bucket": source_bucket,
        "source_key": bronze_key,
        "users_count": len(users_df),
        "posts_count": len(posts_df),
        "post_children_count": len(post_children_df),
    }

def normalize_hn_hit(hit: dict):
    tags = hit.get("_tags") or []

    source_post_id = hit.get("objectID")
    author = hit.get("author")

    if source_post_id is None or author is None:
        return None
    
    hit_type = None
    if("ask_hn" in tags):
        hit_type = "ask_hn"
    elif("job" in tags):
        hit_type = "job"
    elif("poll" in tags):
        hit_type = "poll"
    elif("story" in tags):
        hit_type = "story"
    elif ("comment" in tags):
        hit_type = "comment"
    else: return None


    post_id = hashlib.sha256(f"HN_POST|{source_post_id}".encode("utf-8")).hexdigest()
    user_id = hashlib.sha256(f"HN_USER|{author}".encode("utf-8")).hexdigest()
    
    content = ""
    if (hit_type == "story"):
        content = hit.get("story_text") or ""
    elif (hit_type == "comment"):
        content = hit.get("comment_text") or ""
    if (hit_type == "job" or hit_type=="poll"):
        content = hit.get("title") or ""

    content = re.sub(CLEANR, '', content)

    created_at = None

    if hit.get("created_at_i") is not None:
        created_at = (
            datetime
            .fromtimestamp(int(hit.get("created_at_i")), tz=timezone.utc)
            .isoformat()
            .replace("+00:00", "Z")
        )
    
    post_data = {
        "id" : post_id,
        "original_id" : hit.get("objectID"),
        "created_at" : created_at,
        "author" : user_id,
        "content" : content,
        "type" : hit_type,
        "parent" : hit.get("parent_id"),
        "score" : hit.get("points")
    }

    post_children = []

    for child in hit.get("children") or []:
        child_id = hashlib.sha256(f"HN_POST|{child}".encode("utf-8")).hexdigest()

        post_children.append({
            "platform": "HN",
            "parent_id": post_id,
            "child_id": child_id,
        })

    return post_data, post_children

def normalize_hn_post(bucket_name, key):
    posts = []
    post_children = []
    
    raw_bytes = read_s3_object(bucket_name, key)
    payload = json.loads(raw_bytes.decode("utf-8"))

    for hit in payload.get("hits", []):
        normalized = normalize_hn_hit(hit)

        if normalized is None:
            continue

        post_data, children_data = normalized

        posts.append(post_data)
        post_children.extend(children_data)

    return pd.DataFrame(), pd.DataFrame(posts), pd.DataFrame(post_children)

def normalize_hn_user(raw_user: dict):
    username = raw_user.get("id")
    if not username:
        return None

    user_id = hashlib.sha256(f"HN_USER|{username}".encode("utf-8")).hexdigest()

    created = raw_user.get("created")
    created_at = None
    if created is not None:
        created_at = (
            datetime.fromtimestamp(int(created), tz=timezone.utc)
            .isoformat()
            .replace("+00:00", "Z")
        )

    return {
        "id": user_id,
        "username": username,
        "platform": "HN",
        "karma_score": raw_user.get("karma"),
        "is_verified": None,
        "timestamp": created_at,
        "followers": None,
    }

def process_hn_manifest(source_bucket, bronze_key):
    manifest = json.loads(read_s3_object(source_bucket, bronze_key).decode("utf-8"))
    users_prefix = manifest["users_prefix"]

    raw_users = []
    paginator = s3.get_paginator("list_objects_v2")

    for page in paginator.paginate(Bucket=source_bucket, Prefix=users_prefix):
        for obj in page.get("Contents", []):
            key = obj["Key"]
            if not key.endswith(".json"):
                continue

            raw_user = json.loads(read_s3_object(source_bucket, key).decode("utf-8"))
            normalized = normalize_hn_user(raw_user)
            if normalized is not None:
                raw_users.append(normalized)

    users_df = pd.DataFrame(raw_users)
    return users_df, pd.DataFrame(), pd.DataFrame()

def normalize_x_file(bucket_name, key):
    raw_bytes = read_s3_object(bucket_name, key)
    text = raw_bytes.decode("utf-8-sig")

    dataset_df = pd.read_csv(io.StringIO(text))

    users_df = pd.DataFrame()

    users_df["username"] = dataset_df["user_name"].astype("string").str.strip()
    users_df["platform"] = "X"
    users_df["karma_score"] = None

    users_df["is_verified"] = (
        dataset_df["user_verified"]
        .astype("string")
        .str.lower()
        .map({"true": True, "false": False})
    )

    users_df["timestamp"] = (
        pd.to_datetime(dataset_df["user_created"], utc=True, errors="coerce")
        .dt.strftime("%Y-%m-%dT%H:%M:%SZ")
    )

    users_df["followers"] = pd.to_numeric(
        dataset_df["user_followers"],
        errors="coerce"
    ).astype("Int64")

    users_df["id"] = users_df.apply(
        lambda row: hashlib.sha256(
            f"X_USER|{row['username']}|{row['timestamp']}".encode("utf-8")
        ).hexdigest(),
        axis=1,
    )

    users_df = users_df[
        [
            "id",
            "username",
            "platform",
            "karma_score",
            "is_verified",
            "timestamp",
            "followers",
        ]
    ]

    posts_df = pd.DataFrame()

    posts_df["created_at"] = (
        pd.to_datetime(dataset_df["date"], utc=True, errors="coerce")
        .dt.strftime("%Y-%m-%dT%H:%M:%SZ")
    )

    posts_df["author"] = users_df["id"]
    posts_df["content"] = dataset_df["text"]
    posts_df["type"] = None
    posts_df["parent"] = None
    posts_df["score"] = None
    posts_df["original_id"] = None
    posts_df["id"] = posts_df.apply(
        lambda row: hashlib.sha256(
            f"X_POST|{row['created_at']}|{row['author']}|{row['content']}".encode("utf-8")
        ).hexdigest(),
        axis=1,
    )

    posts_df = posts_df[
        [
            "id",
            "original_id",
            "created_at",
            "author",
            "content",
            "type",
            "parent",
            "score",
        ]
    ]

    users_df = users_df.drop_duplicates(subset=["id"])

    return users_df, posts_df, pd.DataFrame()
