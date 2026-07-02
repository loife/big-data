import json
import os
import urllib.request

DISCORD_WEBHOOK_URL = os.environ["DISCORD_WEBHOOK_URL"]


def _post_to_discord(content):
    payload = json.dumps({"content": content}).encode("utf-8")
    req = urllib.request.Request(
        DISCORD_WEBHOOK_URL,
        data=payload,
        headers={
            "Content-Type": "application/json",
            "User-Agent": "social-medias-notifier/1.0",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        return resp.status


def notify(event, context):
    for record in event.get("Records", []):
        sns = record.get("Sns", {})
        subject = sns.get("Subject") or "Job failed"

        message = sns.get("Message", "")
        alarm_name = None
        try:
            parsed = json.loads(message)
            alarm_name = parsed.get("AlarmName")
            reason = parsed.get("NewStateReason", "")
        except (json.JSONDecodeError, TypeError):
            reason = message

        title = alarm_name or subject
        content = f"**{title}**\n{reason}"[:1900]
        
        status = _post_to_discord(content)
        print(f"[notifier] sent to discord (status={status}) for {title}")

    return {"status": "sent"}