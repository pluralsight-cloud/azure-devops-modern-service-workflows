#!/usr/bin/env bash
# Replace the course's account-bound names in YOUR copy of the sample pipeline.
# The sample uses placeholder names (organization globomantics-devops, project
# globomantics-orders, feed globomantics-packages, app app-globomantics-orders-stg);
# replace them with names from your own organization and subscription.
#
#   bash set-my-names.sh --org <your-org> --project <your-project> --feed <your-feed> \
#        --app <your-unique-app-name> [--service-connection <name>]
#
# Edits only module-01-setting-up-traceable-delivery/orders-api/azure-pipelines.yml
# and .../ci/build-stage.yml. Safe to run again with new values. Local only:
# no network, no Azure DevOps or Azure calls. Commit the result to your own repo.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app_dir="$root/module-01-setting-up-traceable-delivery/orders-api"
org="" project="" feed="" app="" sc=""

usage() { sed -n '2,12p' "${BASH_SOURCE[0]}"; exit 64; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --org) org="${2:-}"; shift 2 ;;
    --project) project="${2:-}"; shift 2 ;;
    --feed) feed="${2:-}"; shift 2 ;;
    --app) app="${2:-}"; shift 2 ;;
    --service-connection) sc="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done
[[ -n "$org" && -n "$project" && -n "$feed" && -n "$app" ]] || usage

python3 - "$app_dir" "$org" "$project" "$feed" "$app" "$sc" <<'PY'
import pathlib, re, sys
app_dir, org, project, feed, app, sc = sys.argv[1:]
checks = {
    "--org": (org, r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,48}[A-Za-z0-9])?"),
    "--project": (project, r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}"),
    "--feed": (feed, r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}"),
    "--app": (app, r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,58}[A-Za-z0-9])?"),
}
if sc:
    checks["--service-connection"] = (sc, r"[A-Za-z0-9][A-Za-z0-9._-]{0,63}")
for flag, (value, pattern) in checks.items():
    if not re.fullmatch(pattern, value):
        sys.exit(f"STOP: {flag} {value!r} is not a valid name (letters, digits, '-', no spaces). Nothing was changed.")

root = pathlib.Path(app_dir)
entry, stage = root / "azure-pipelines.yml", root / "ci" / "build-stage.yml"
feed_url = f"https://pkgs.dev.azure.com/{org}/{project}/_packaging/{feed}/nuget/v3/index.json"
edits = [
    (stage, r"https://pkgs\.dev\.azure\.com/[^/\s\"]+/[^/\s\"]+/_packaging/[^/\s\"]+/nuget/v3/index\.json", feed_url),
    (stage, r"(?m)(displayName: Publish contracts to )\S+$", rf"\g<1>{feed}"),
    (entry, r"(?m)^(\s*appName: )\S+$", rf"\g<1>{app}"),
]
if sc:
    edits.append((entry, r"(?m)^(\s*azureSubscription: )\S+$", rf"\g<1>{sc}"))
texts = {p: p.read_text() for p in (entry, stage)}
for path, pattern, repl in edits:
    texts[path], n = re.subn(pattern, repl, texts[path])
    if n != 1:
        sys.exit(f"STOP: expected exactly one match for {pattern!r} in {path.name}, found {n}. Nothing was changed.")
for path, text in texts.items():
    path.write_text(text)
print(f"Feed URL:            {feed_url}")
print(f"App Service name:    {app}")
print(f"Service connection:  {sc or '(unchanged: sc-globomantics-orders-azure)'}")
print("Updated azure-pipelines.yml and ci/build-stage.yml. Review with: git diff")
PY
