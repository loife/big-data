import os

import awswrangler as wr
import pandas as pd
import pg8000

GOLD_BUCKET = os.environ["GOLD_BUCKET"]
PG_HOST = os.environ["PG_HOST"]
PG_PORT = int(os.environ.get("PG_PORT", "5432"))
PG_DB = os.environ.get("PG_DB", "metrics")
PG_USER = os.environ["PG_USER"]
PG_PASSWORD = os.environ["PG_PASSWORD"]

# Sve gold tabele koje gold Lambda upisuje u S3
GOLD_TABLES = [
    "daily_post_metrics",
    "daily_users_metric",
    "top_x_followers",
    "top_hn_karma_highest",
    "top_hn_karma_lowest",
    "top_hn_jobs",
    "top_hn_stories",
    "data_quality_score",
]


def _read_table(table):
    path = f"s3://{GOLD_BUCKET}/{table}/"
    try:
        return wr.s3.read_parquet(path=path, dataset=True)
    except (wr.exceptions.NoFilesFound, FileNotFoundError):
        return pd.DataFrame()


def load(event, context):
    con = pg8000.connect(
        host=PG_HOST,
        port=PG_PORT,
        database=PG_DB,
        user=PG_USER,
        password=PG_PASSWORD,
    )

    results = {}
    try:
        for table in GOLD_TABLES:
            df = _read_table(table)
            if df.empty:
                print(f"[loader] {table}: nema podataka, preskačem")
                results[table] = 0
                continue

            wr.postgresql.to_sql(
                df=df,
                con=con,
                table=table,
                schema="public",
                mode="overwrite",
                index=False,
            )
            print(f"[loader] {table}: upisano {len(df)} redova")
            results[table] = len(df)

        con.commit()
    finally:
        con.close()

    return {"status": "success", "loaded": results}
