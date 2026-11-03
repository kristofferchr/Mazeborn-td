#!/usr/bin/env python3
"""Downloads the file(s) of a free itch.io asset page without logging in.

Usage: scripts/itch_download.py <creator> <slug> <out.zip>

Uses the same calls as the "Download" button: the page's CSRF token, then
POST /<slug>/file/<upload_id> which answers with a signed CDN URL. Only the
first upload of the page is saved. Requires `pip install requests`.
"""

import re
import sys

import requests


def main() -> None:
    creator, slug, out = sys.argv[1:4]
    session = requests.Session()
    session.headers["User-Agent"] = "Mozilla/5.0 (mazeborn-td asset fetch)"
    base = f"https://{creator}.itch.io/{slug}"
    page = session.get(base, timeout=60).text
    csrf = re.search(r'name="csrf_token" value="([^"]+)"', page).group(1)
    download_page = session.post(
        base + "/download_url", data={"csrf_token": csrf}, timeout=60
    ).json()["url"]
    uploads = re.findall(r'data-upload_id="(\d+)"', session.get(download_page, timeout=60).text)
    if not uploads:
        sys.exit(f"no uploads found on {base}")
    url = session.post(
        f"{base}/file/{uploads[0]}?source=view_game&as_props=1",
        data={"csrf_token": csrf},
        timeout=60,
    ).json()["url"]
    with session.get(url, stream=True, timeout=600) as resp, open(out, "wb") as f:
        resp.raise_for_status()
        for chunk in resp.iter_content(1 << 20):
            f.write(chunk)
    print(f"{slug}: {out}")


if __name__ == "__main__":
    main()
