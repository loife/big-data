import json
import os
import urllib.request

DISCORD_WEBHOOK_URL = os.environ["DISCORD_WEBHOOK_URL"]

# pomocna funkcija koja salje jednu poruku na diskord
def _post_to_discord(content):
    payload = json.dumps({"content": content}).encode("utf-8")  # discord ocekuje json
    req = urllib.request.Request(       # kreira se http zahtjev
        DISCORD_WEBHOOK_URL,
        data=payload,
        headers={
            "Content-Type": "application/json",
            "User-Agent": "social-medias-notifier/1.0",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=10) as resp:       # salje http zahtjev
        return resp.status

# glavna funkcija koju aws automatski poziva
def notify(event, context):
    for record in event.get("Records", []):     # prolazi kroz sve poruke
        sns = record.get("Sns", {}) # uzima sns podatke
        subject = sns.get("Subject") or "Job failed"    # izvlaci subject i message

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