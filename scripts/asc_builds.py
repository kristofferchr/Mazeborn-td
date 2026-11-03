#!/usr/bin/env python3
"""Show recent TestFlight uploads and builds for Mazeborn TD (read-only).

Needs ASC_KEY_ID, ASC_ISSUER_ID and ASC_PRIVATE_KEY_BASE64 in the environment
(set in the Claude Code cloud environment and as GitHub secrets) and
`pip install pyjwt cryptography`.

Usage: scripts/asc_builds.py [--wait BUILD_NUMBER]
  --wait  poll every minute (max 45 min) until that build is processed;
          exits 1 if Apple reports it as invalid or failed.
"""
import base64
import json
import os
import sys
import time
import urllib.request

import jwt

BUNDLE_ID = "kristofferchr.MazebornTD"
API = "https://api.appstoreconnect.apple.com"


def get(path):
    key = base64.b64decode(os.environ["ASC_PRIVATE_KEY_BASE64"]).decode()
    now = int(time.time())
    token = jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )
    req = urllib.request.Request(API + path, headers={"Authorization": "Bearer " + token})
    with urllib.request.urlopen(req) as resp:
        return json.load(resp)


def status(app_id):
    uploads = get(f"/v1/apps/{app_id}/buildUploads?limit=5")["data"]
    builds = get(f"/v1/builds?filter[app]={app_id}&sort=-uploadedDate&limit=5"
                 "&fields[builds]=version,processingState,uploadedDate")["data"]
    return (
        {u["attributes"]["cfBundleVersion"]: u["attributes"]["state"] for u in uploads},
        {b["attributes"]["version"]: b["attributes"]["processingState"] for b in builds},
    )


def main():
    app_id = get(f"/v1/apps?filter[bundleId]={BUNDLE_ID}")["data"][0]["id"]
    wait = sys.argv[2] if len(sys.argv) > 2 and sys.argv[1] == "--wait" else None
    for _ in range(45 if wait else 1):
        uploads, builds = status(app_id)
        print(time.strftime("%H:%M:%S"))
        for number, state in uploads.items():
            errors = "; ".join(e.get("description", str(e)) for e in state.get("errors", []))
            print(f"  upload {number}: {state['state']} {errors}".rstrip())
        for number, state in builds.items():
            print(f"  build  {number}: {state}")
        if not wait:
            return 0
        if builds.get(wait) == "VALID":
            return 0
        if builds.get(wait) in ("INVALID", "FAILED") or uploads.get(wait, {}).get("state") == "FAILED":
            return 1
        time.sleep(60)
    print(f"build {wait} not processed after 45 min", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
