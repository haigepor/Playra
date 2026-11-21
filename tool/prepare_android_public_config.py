"""Stage the two distributable CliCli settings for an Android release build."""

import json
import os
from pathlib import Path
from urllib.parse import urlsplit


def main():
    settings = {
        key: os.environ.get(key, "").strip()
        for key in ("CLICLI_PUBLIC_CLIENT_ID", "CLICLI_PUBLIC_SERVICE_URL")
    }
    missing = [key for key, value in settings.items() if not value]
    if missing:
        raise SystemExit("Missing GitHub Actions variable(s): " + ", ".join(missing))

    service_url = settings["CLICLI_PUBLIC_SERVICE_URL"]
    url_error = ("CLICLI_PUBLIC_SERVICE_URL must be an HTTPS service URL "
                 "without credentials, query parameters or a fragment.")
    try:
        url = urlsplit(service_url)
        port = url.port
    except ValueError:
        raise SystemExit(url_error) from None
    if (url.scheme != "https" or not url.hostname or port == 0 or
            url.username is not None or "?" in service_url or "#" in service_url or
            "\\" in service_url or any(char.isspace() for char in service_url)):
        raise SystemExit(url_error)

    asset = Path("android/app/src/release/assets/playra/clicli-public.json")
    asset.parent.mkdir(parents=True, exist_ok=True)
    config = {"clientId": settings["CLICLI_PUBLIC_CLIENT_ID"], "serviceUrl": service_url}
    asset.write_text(json.dumps(config), encoding="utf-8")


if __name__ == "__main__":
    main()
