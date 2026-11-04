#!/usr/bin/env python3
"""Show recent TestFlight uploads and builds for Mazeborn TD, or wait for one.

Read-only. Needs ASC_KEY_ID, ASC_ISSUER_ID and ASC_PRIVATE_KEY_BASE64 in the
environment (set in the Claude Code cloud environment and as GitHub secrets)
and `pip install pyjwt cryptography`.

Usage: scripts/asc_builds.py [--wait BUILD_NUMBER] [--version X.Y.Z] [--timeout MINUTES]
  --wait     poll every minute until that build is processed by Apple.
             Exits 0 when it is VALID, 1 if the upload or build fails
             (FAILED/INVALID) or if it is not processed within --timeout.
  --version  only match the build in that version (CFBundleShortVersionString).
  --timeout  minutes to wait (default 45).

Also used as a module by scripts/asc_whats_new.py.
"""
import argparse
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

BUNDLE_ID = "kristofferchr.MazebornTD"
API = "https://api.appstoreconnect.apple.com"
TRANSIENT_HTTP = (429, 500, 502, 503, 504)


def _token():
    import jwt  # imported lazily so --dry-run works without pyjwt

    key = base64.b64decode(os.environ["ASC_PRIVATE_KEY_BASE64"]).decode()
    now = int(time.time())
    return jwt.encode(
        {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"},
        key,
        algorithm="ES256",
        headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
    )


def have_credentials():
    return all(os.environ.get(v) for v in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY_BASE64"))


def request(method, path, body=None, attempts=4):
    """Calls the App Store Connect API and returns the decoded JSON (or None).

    Network errors and 429/5xx are retried with backoff; other HTTP errors
    raise urllib.error.HTTPError with Apple's error text in the message.
    """
    data = json.dumps(body).encode() if body is not None else None
    for attempt in range(attempts):
        req = urllib.request.Request(API + path, data=data, method=method)
        req.add_header("Authorization", "Bearer " + _token())
        if data is not None:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                raw = resp.read()
                return json.loads(raw) if raw else None
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")
            if e.code in TRANSIENT_HTTP and attempt + 1 < attempts:
                time.sleep(2 ** (attempt + 1))
                continue
            raise urllib.error.HTTPError(e.url, e.code, f"{e.reason}: {detail}", e.headers, None) from None
        except (urllib.error.URLError, TimeoutError, ConnectionError):
            if attempt + 1 < attempts:
                time.sleep(2 ** (attempt + 1))
                continue
            raise
    raise AssertionError("unreachable")


def get(path):
    return request("GET", path)


def app_id():
    return get(f"/v1/apps?filter[bundleId]={BUNDLE_ID}")["data"][0]["id"]


def find_build(app, number, version=None):
    """Returns the build resource for a build number (and version), or None."""
    query = {"filter[app]": app, "filter[version]": str(number), "limit": "1"}
    if version:
        query["filter[preReleaseVersion.version]"] = version
    data = get("/v1/builds?" + urllib.parse.urlencode(query))["data"]
    return data[0] if data else None


def find_upload(app, number, version=None):
    """Returns the attributes of the newest upload with that build number, or None."""
    query = {"filter[cfBundleVersion]": str(number), "limit": "5"}
    for upload in get(f"/v1/apps/{app}/buildUploads?" + urllib.parse.urlencode(query))["data"]:
        attrs = upload["attributes"]
        if not version or attrs.get("cfBundleShortVersionString") == version:
            return attrs
    return None


def upload_errors(upload):
    state = (upload or {}).get("state") or {}
    return "; ".join(e.get("description", str(e)) for e in state.get("errors", []))


def status(app):
    uploads = get(f"/v1/apps/{app}/buildUploads?limit=5")["data"]
    builds = get(
        f"/v1/builds?filter[app]={app}&sort=-uploadedDate&limit=5&fields[builds]=version,processingState,uploadedDate"
    )["data"]
    return (
        {u["attributes"]["cfBundleVersion"]: u["attributes"] for u in uploads},
        {b["attributes"]["version"]: b["attributes"]["processingState"] for b in builds},
    )


def error(message):
    prefix = "::error::" if os.environ.get("GITHUB_ACTIONS") else "error: "
    print(prefix + message, file=sys.stderr)


def show(app):
    uploads, builds = status(app)
    print(time.strftime("%H:%M:%S"))
    for number, attrs in uploads.items():
        line = f"  upload {number} ({attrs.get('cfBundleShortVersionString')}): {attrs['state']['state']}"
        print(f"{line} {upload_errors(attrs)}".rstrip())
    for number, state in builds.items():
        print(f"  build  {number}: {state}")


def wait(app, number, version, timeout_min):
    deadline = time.time() + timeout_min * 60
    label = f"build {number}" + (f" ({version})" if version else "")
    last = None
    while True:
        upload = find_upload(app, number, version)
        build = find_build(app, number, version)
        upload_state = ((upload or {}).get("state") or {}).get("state")
        build_state = build["attributes"]["processingState"] if build else None
        now = (upload_state, build_state)
        if now != last:
            print(f"{time.strftime('%H:%M:%S')} {label}: upload={upload_state or '-'} build={build_state or '-'}")
            last = now
        if build_state == "VALID":
            detail = get(f"/v1/builds/{build['id']}/buildBetaDetail")["data"]["attributes"]
            print(f"{label} is VALID; internal TestFlight state: {detail.get('internalBuildState')}")
            return 0
        if build_state in ("INVALID", "FAILED") or upload_state == "FAILED":
            error(f"{label} was rejected by Apple: upload={upload_state} build={build_state} {upload_errors(upload)}")
            return 1
        if time.time() >= deadline:
            error(f"{label} was not processed within {timeout_min} min (upload={upload_state} build={build_state})")
            return 1
        time.sleep(60)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--wait", metavar="BUILD_NUMBER")
    parser.add_argument("--version")
    parser.add_argument("--timeout", type=int, default=45, metavar="MINUTES")
    args = parser.parse_args()
    app = app_id()
    if args.wait:
        return wait(app, args.wait, args.version, args.timeout)
    show(app)
    return 0


if __name__ == "__main__":
    sys.exit(main())
