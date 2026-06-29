import os
from datetime import datetime, timezone, timedelta

import pandas as pd
import awswrangler as wr

SILVER_BUCKET = os.environ["SILVER_BUCKET"]
GOLD_BUCKET = os.environ["GOLD_BUCKET"]

HN_POST_TYPES = ["story", "ask_hn", "comment", "job", "poll"]


def _resolve_date(event):
    if event and event.get("date"):
        return event["date"]
    yesterday = datetime.now(timezone.utc).date() - timedelta(days=1)
    return yesterday.strftime("%Y-%m-%d")


def _read_safe(path, **kwargs):
    try:
        dfs = list(
            wr.s3.read_parquet(
                path=path,
                dataset=True,
                chunked=True,
                **kwargs,
            )
        )
    except (wr.exceptions.NoFilesFound, FileNotFoundError):
        return pd.DataFrame()
    if not dfs:
        return pd.DataFrame()
    return pd.concat(dfs, ignore_index=True)


def read_users(platform=None):
    path = f"s3://{SILVER_BUCKET}/users/"
    if platform is not None:
        return _read_safe(path, partition_filter=lambda p: p["platform"] == platform)
    return _read_safe(path)


def read_posts_for_date(target_date):
    path = f"s3://{SILVER_BUCKET}/posts/"
    return _read_safe(path, partition_filter=lambda p: p["date"] == target_date)


def read_post_children():
    return _read_safe(f"s3://{SILVER_BUCKET}/post_children/")


def _write(df, table, partition_cols):
    if df is None or df.empty:
        print(f"[gold] {table}: nothing to write")
        return 0
    wr.s3.to_parquet(
        df=df,
        path=f"s3://{GOLD_BUCKET}/{table}/",
        dataset=True,
        mode="overwrite_partitions",
        partition_cols=partition_cols,
    )
    print(f"[gold] {table}: wrote {len(df)} rows (partitions={partition_cols})")
    return len(df)


def metric_daily_post_counts(posts, target_date):
    if posts.empty:
        counts = pd.Series(0, index=HN_POST_TYPES)
    else:
        hn = posts[posts["type"].notna()]
        if hn.empty:
            counts = pd.Series(0, index=HN_POST_TYPES)
        else:
            counts = hn.groupby("type").size().reindex(HN_POST_TYPES, fill_value=0)

    df = counts.rename_axis("post_type").reset_index(name="post_count")
    df.insert(0, "date", target_date)
    return df


def metric_daily_users(users, target_date):
    if not users.empty:
        reg_date = pd.to_datetime(
            users["timestamp"], utc=True, errors="coerce"
        ).dt.strftime("%Y-%m-%d")
        users = users.assign(_reg_date=reg_date)

    rows = []
    for platform in ["HN", "X"]:
        if users.empty:
            total = new = 0
        else:
            pu = users[users["platform"] == platform]
            total = int(len(pu))
            new = int((pu["_reg_date"] == target_date).sum())
        rows.append(
            {
                "date": target_date,
                "platform": platform,
                "total_users": total,
                "new_users": new,
            }
        )
    return pd.DataFrame(rows)


def _top_users(users, value_col, ascending, target_date, keep_cols):
    if users.empty:
        return pd.DataFrame()
    df = users.copy()
    df[value_col] = pd.to_numeric(df[value_col], errors="coerce")
    df = df.dropna(subset=[value_col])
    if df.empty:
        return pd.DataFrame()
    df = df.sort_values(value_col, ascending=ascending).head(10).reset_index(drop=True)
    df["rank"] = df.index + 1
    df["snapshot_date"] = target_date
    return df[["snapshot_date", "rank"] + keep_cols]


def metric_top_x_followers(target_date):
    xu = read_users("X")
    return _top_users(xu, "followers", False, target_date, ["id", "username", "followers"])


def metric_top_hn_karma(target_date, ascending):
    hu = read_users("HN")
    return _top_users(hu, "karma_score", ascending, target_date, ["id", "username", "karma_score"])


def _top_posts_by_score(posts, post_type, target_date):
    if posts.empty:
        return pd.DataFrame()
    df = posts[posts["type"] == post_type].copy()
    if df.empty:
        return pd.DataFrame()
    df["score"] = pd.to_numeric(df["score"], errors="coerce")
    df = df.dropna(subset=["score"])
    if df.empty:
        return pd.DataFrame()
    df = df.sort_values("score", ascending=False).head(10).reset_index(drop=True)
    df["rank"] = df.index + 1
    df["date"] = target_date
    return df[["date", "rank", "id", "original_id", "author", "content", "score"]]


def kpi_data_quality(tables, run_date):
    rows = []
    for name, df in tables.items():
        if df is None or df.empty:
            total = non_null = 0
            score = 0.0
        else:
            total = int(df.size)
            non_null = int(df.notna().sum().sum())
            score = round(100.0 * non_null / total, 2) if total else 0.0
        rows.append(
            {
                "run_date": run_date,
                "table_name": name,
                "total_cells": total,
                "non_null_cells": non_null,
                "quality_score": score,
            }
        )
    return pd.DataFrame(rows)


def transform_gold(event, context):
    target_date = _resolve_date(event or {})
    print(f"[gold] transforming for date={target_date}")

    users = read_users()
    posts = read_posts_for_date(target_date)
    post_children = read_post_children()

    written = {}

    written["daily_post_metrics"] = _write(
        metric_daily_post_counts(posts, target_date), "daily_post_metrics", ["date"]
    )

    written["daily_users_metric"] = _write(
        metric_daily_users(users, target_date), "daily_users_metric", ["platform", "date"]
    )

    written["top_x_followers"] = _write(
        metric_top_x_followers(target_date), "top_x_followers", ["snapshot_date"]
    )

    written["top_hn_karma_highest"] = _write(
        metric_top_hn_karma(target_date, ascending=False), "top_hn_karma_highest", ["snapshot_date"]
    )

    written["top_hn_karma_lowest"] = _write(
        metric_top_hn_karma(target_date, ascending=True), "top_hn_karma_lowest", ["snapshot_date"]
    )

    written["top_hn_jobs"] = _write(
        _top_posts_by_score(posts, "job", target_date), "top_hn_jobs", ["date"]
    )

    written["top_hn_stories"] = _write(
        _top_posts_by_score(posts, "story", target_date), "top_hn_stories", ["date"]
    )

    written["data_quality_score"] = _write(
        kpi_data_quality(
            {"users": users, "posts": posts, "post_children": post_children}, target_date
        ),
        "data_quality_score",
        ["run_date"],
    )

    return {"status": "success", "date": target_date, "written": written}