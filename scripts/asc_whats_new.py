#!/usr/bin/env python3
"""Sets TestFlight "What to Test" for a Mazeborn TD build from the git history.

The text lists the changes since:
  - the previous v* tag, when building a tag (GITHUB_REF_TYPE=tag or --tag);
  - otherwise, or if there is no earlier tag, the commit of the last
    successful iOS TestFlight workflow run (looked up with `gh`);
  - for manual runs (workflow_dispatch) on a branch: the last 15 merged PRs.
It is trimmed to Apple's limit of 4000 characters.

Usage: scripts/asc_whats_new.py --build N [--version X.Y.Z] [--tag vX.Y.Z]
                                [--locale LOCALE ...] [--timeout MIN] [--dry-run]
  --build    build number (CFBundleVersion) of the uploaded build.
  --version  marketing version (CFBundleShortVersionString) of the build.
  --tag      tag being built (default: GITHUB_REF_NAME when GITHUB_REF_TYPE=tag).
  --locale   betaBuildLocalizations locale(s); default: the app's primary
             locale plus any TestFlight (beta app) localizations.
  --timeout  minutes to wait for the build to show up in App Store Connect.
  --dry-run  print the text and the API calls it would make; only reads.

Needs the same ASC_* environment variables as scripts/asc_builds.py (without
them, --dry-run only prints the text). Writes the text to
$GITHUB_STEP_SUMMARY when it is set.
"""
import argparse
import json
import os
import re
import subprocess
import sys
import time
import urllib.error

sys.dont_write_bytecode = True  # no scripts/__pycache__ from the import below
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asc_builds as asc  # noqa: E402

LIMIT = 4000  # Apple's limit for whatsNew
DISPATCH_PRS = 15
WORKFLOW = "ios.yml"
MERGE_RE = re.compile(r"^Merge pull request #(\d+) from (\S+)")


def git(*args):
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout.strip()


def git_ok(*args):
    return subprocess.run(["git", *args], capture_output=True).returncode == 0


def previous_tag(tag):
    """The nearest v* tag before `tag` (on its history), or None."""
    try:
        return git("describe", "--tags", "--abbrev=0", "--match", "v*", f"{tag}^") or None
    except subprocess.CalledProcessError:
        return None


def previous_build_commit(head):
    """Commit of the last successful TestFlight workflow run that is an ancestor of head."""
    repo = os.environ.get("GITHUB_REPOSITORY", "kristofferchr/Mazeborn-td")
    current = os.environ.get("GITHUB_RUN_ID")
    try:
        out = subprocess.run(
            ["gh", "api", f"repos/{repo}/actions/workflows/{WORKFLOW}/runs?status=success&per_page=20",
             "--jq", ".workflow_runs[] | [.id, .head_sha] | @tsv"],
            check=True, capture_output=True, text=True, timeout=60,
        ).stdout
    except (OSError, subprocess.SubprocessError) as e:
        print(f"note: could not look up previous TestFlight runs ({e})", file=sys.stderr)
        return None
    for line in out.splitlines():
        run_id, sha = line.split("\t")
        if run_id == current or sha == head:
            continue
        if git_ok("cat-file", "-e", f"{sha}^{{commit}}") and git_ok("merge-base", "--is-ancestor", sha, head):
            return sha
    return None


def pr_entry(sha, subject, body):
    """('Title (#N)', merge?) for a first-parent commit; PR merges use the PR title."""
    m = MERGE_RE.match(subject)
    if not m:
        return subject, False
    title = next((line.strip() for line in body.splitlines() if line.strip()), "")
    if not title:
        title = git("log", "-1", "--format=%s", f"{sha}^2")
    return f"{title} (#{m.group(1)})", True


def first_parent(rev_range, limit=None, merges_only=False):
    args = ["log", "--first-parent", "--format=%H%x1f%s%x1f%b%x1e"]
    if merges_only:
        args.append("--merges")
    if limit:
        args.append(f"-{limit}")
    # Not git(): str.strip() treats the \x1e/\x1f separators as whitespace.
    out = subprocess.run(["git", *args, rev_range], check=True, capture_output=True, text=True).stdout
    records = [rec.lstrip("\n") for rec in out.split("\x1e")]
    return [(rec.split("\x1f", 2) + ["", ""])[:3] for rec in records if rec]


def changes(rev_range, limit=None, merges_only=False, details=True):
    """Bullet lines, newest first; PR merges get their commit subjects indented below."""
    lines = []
    for sha, subject, body in first_parent(rev_range, limit, merges_only):
        if subject.startswith("Merge branch ") or subject.startswith("Merge remote-tracking branch "):
            continue
        title, merge = pr_entry(sha, subject, body)
        lines.append(f"- {title}")
        if merge and details:
            subjects = git("log", "--no-merges", "--format=%s", f"{sha}^1..{sha}^2").splitlines()
            lines += [f"  · {s}" for s in subjects if s and s != title.rsplit(" (#", 1)[0]]
    return lines


def utf16_len(text):
    return len(text.encode("utf-16-le")) // 2


def fit(header, lines, limit=LIMIT):
    """header + lines within limit; drops trailing (oldest) lines and says how many."""
    text = header + "\n".join(lines)
    if utf16_len(text) <= limit:
        return text
    bullets = sum(1 for line in lines if line.startswith("- "))
    for keep in range(len(lines) - 1, -1, -1):
        kept = lines[:keep]
        rest = bullets - sum(1 for line in kept if line.startswith("- "))
        more = f"- … og {rest} endringer til" if rest else "- …"
        text = header + "\n".join(kept + [more])
        if utf16_len(text) <= limit:
            return text
    return header[:limit]


def whats_new(build, version, tag, head="HEAD"):
    """Returns (text, description of the range used)."""
    title = f"Mazeborn TD {version} (build {build})\n\n" if version else f"Mazeborn TD (build {build})\n\n"
    base, since = None, None
    if tag:
        base = previous_tag(tag)
        since = f"Endringer siden {base}:\n" if base else None
        if not base:
            base = previous_build_commit(git("rev-parse", head))
            since = f"Endringer siden forrige TestFlight-bygg ({base[:7]}):\n" if base else None
    if base:
        detailed = changes(f"{base}..{head}")
        if not detailed:
            return title + f"Ingen nye commits siden {base}.", f"{base}..{head}"
        text = title + since + "\n".join(detailed)
        if utf16_len(text) > LIMIT:  # too long with commit details: PR titles only
            text = fit(title + since, changes(f"{base}..{head}", details=False))
        return text, f"{base}..{head}"
    lines = changes(head, limit=DISPATCH_PRS, merges_only=True, details=False)
    return fit(title + "Siste endringer:\n", lines), f"last {DISPATCH_PRS} merged PRs before {head}"


def locales_for(app, build_id, wanted):
    """Locales to write, and the existing localization id per locale on the build."""
    existing = {}
    if build_id:
        for loc in asc.get(f"/v1/builds/{build_id}/betaBuildLocalizations")["data"]:
            existing[loc["attributes"]["locale"]] = loc["id"]
    if wanted:
        return list(wanted), existing
    attrs = asc.get(f"/v1/apps/{app}?fields[apps]=primaryLocale")["data"]["attributes"]
    beta = [loc["attributes"]["locale"] for loc in asc.get(f"/v1/apps/{app}/betaAppLocalizations")["data"]]
    found = [attrs["primaryLocale"], *beta, *existing]
    return list(dict.fromkeys(found)), existing


def write_calls(build_id, text, locales, existing):
    calls = []
    for locale in locales:
        if locale in existing:
            body = {"data": {"type": "betaBuildLocalizations", "id": existing[locale], "attributes": {"whatsNew": text}}}
            calls.append(("PATCH", f"/v1/betaBuildLocalizations/{existing[locale]}", body))
        else:
            body = {
                "data": {
                    "type": "betaBuildLocalizations",
                    "attributes": {"locale": locale, "whatsNew": text},
                    "relationships": {"build": {"data": {"type": "builds", "id": build_id}}},
                }
            }
            calls.append(("POST", "/v1/betaBuildLocalizations", body))
    return calls


def wait_for_build(app, build, version, timeout_min):
    deadline = time.time() + timeout_min * 60
    while True:
        found = asc.find_build(app, build, version)
        if found:
            return found
        upload = asc.find_upload(app, build, version)
        if ((upload or {}).get("state") or {}).get("state") == "FAILED":
            asc.error(f"upload of build {build} failed: {asc.upload_errors(upload)}")
            return None
        if time.time() >= deadline:
            asc.error(f"build {build} did not show up in App Store Connect within {timeout_min} min")
            return None
        print(f"{time.strftime('%H:%M:%S')} waiting for build {build} to show up in App Store Connect")
        time.sleep(30)


def apply(calls, deadline):
    """Sends the writes; retries 409 (build still processing) until the deadline."""
    for method, path, body in calls:
        while True:
            try:
                asc.request(method, path, body)
                print(f"{method} {path}: ok ({body['data']['attributes'].get('locale', 'update')})")
                break
            except urllib.error.HTTPError as e:
                if e.code == 409 and time.time() < deadline:
                    print(f"{method} {path}: {e.code}, retrying in 60 s ({e.reason})")
                    time.sleep(60)
                    continue
                asc.error(f"{method} {path} failed: HTTP {e.code} {e.reason}")
                return 1
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--build", required=True)
    parser.add_argument("--version")
    default_tag = os.environ.get("GITHUB_REF_NAME") if os.environ.get("GITHUB_REF_TYPE") == "tag" else None
    parser.add_argument("--tag", default=default_tag)
    parser.add_argument("--locale", action="append", default=[])
    parser.add_argument("--timeout", type=int, default=30, metavar="MINUTES")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    head = args.tag or "HEAD"
    text, used = whats_new(args.build, args.version, args.tag, head)
    print(f"What to Test ({used}, {utf16_len(text)}/{LIMIT} chars):\n{'-' * 60}\n{text}\n{'-' * 60}")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write(f"### What to Test (build {args.build})\n\n```\n{text}\n```\n")

    if args.dry_run and not asc.have_credentials():
        print("dry run without ASC_* credentials: skipping App Store Connect lookups")
        return 0
    app = asc.app_id()
    print(f"GET /v1/apps?filter[bundleId]={asc.BUNDLE_ID} -> app {app}")
    if args.dry_run:
        found = asc.find_build(app, args.build, args.version)
        print(f"GET /v1/builds?filter[app]={app}&filter[version]={args.build}"
              f"{'&filter[preReleaseVersion.version]=' + args.version if args.version else ''}"
              f" -> {found['id'] if found else 'not found (the workflow waits for it)'}")
    else:
        found = wait_for_build(app, args.build, args.version, args.timeout)
        if not found:
            return 1
    build_id = found["id"] if found else "<build id>"
    locales, existing = locales_for(app, found and found["id"], args.locale)
    print(f"locales: {', '.join(locales)} (existing on build: {', '.join(existing) or 'none'})")
    calls = write_calls(build_id, text, locales, existing)
    if args.dry_run:
        for method, path, body in calls:
            print(f"would {method} {path}\n{json.dumps(body, ensure_ascii=False, indent=2)}")
        return 0
    return apply(calls, time.time() + args.timeout * 60)


if __name__ == "__main__":
    sys.exit(main())
