#!/usr/bin/env python3
"""Static checks for the Module 1 sample pipeline YAML (no Azure DevOps needed).

Usage: python3 check-yaml.py [path-to-orders-api-dir]
Requires PyYAML (see ../requirements.txt). This is a structural/safety check of
the files, NOT Azure DevOps' own YAML validation; only the service compiles the
pipeline for real.
"""
import sys
import re
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("PyYAML missing: python3 -m pip install -r requirements.txt")

root = Path(sys.argv[1] if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "orders-api")
failures = []


def expect(cond, msg):
    print(("ok   " if cond else "FAIL ") + msg)
    if not cond:
        failures.append(msg)


entry = yaml.safe_load((root / "azure-pipelines.yml").read_text())
stage = yaml.safe_load((root / "ci" / "build-stage.yml").read_text())

params = {p["name"]: p for p in entry["parameters"]}
expect(params["publishPackages"]["default"] is False, "entry: publishPackages defaults to false")
expect(params["deployStaging"]["default"] is False, "entry: deployStaging defaults to false")
expect("pr" not in entry, "entry: no YAML `pr:` trigger (Azure Repos uses a branch policy)")
expect(entry["trigger"]["branches"]["include"] == ["main"], "entry: CI trigger includes only main")
expect(entry["stages"][0]["template"] == "ci/build-stage.yml", "entry: first stage is the build template")

cond = [s for s in entry["stages"] if isinstance(s, dict) and any(k.startswith("${{ if") for k in s)]
expect(len(cond) == 1 and "eq(parameters.deployStaging, true)" in list(cond[0])[0],
       "entry: Staging stage exists only behind deployStaging == true")
staging = cond[0][list(cond[0])[0]][0]
dep = staging["jobs"][0]
expect(dep["environment"] == "staging", "Staging deployment targets environment `staging`")
app_name = str(dep["strategy"]["runOnce"]["deploy"]["steps"][-1]["inputs"]["appName"])
expect(re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,58}[A-Za-z0-9])?", app_name) is not None,
       f"Staging deploys to a valid App Service name ({app_name})")

sparams = {p["name"]: p for p in stage["parameters"]}
expect(sparams["publishPackages"]["default"] is False, "template: publishPackages defaults to false")
job = stage["stages"][0]["jobs"][0]
expect(stage["stages"][0]["stage"] == "Build", "template: stage is named Build")
expect(job["pool"]["vmImage"] == "ubuntu-24.04", "template: hosted image ubuntu-24.04")
expect(isinstance(job.get("timeoutInMinutes"), int) and 0 < job["timeoutInMinutes"] <= 30,
       "template: Prepare job sets an explicit timeoutInMinutes (<= 30)")
expect(isinstance(dep.get("timeoutInMinutes"), int) and 0 < dep["timeoutInMinutes"] <= 30,
       "entry: Staging deployment job sets an explicit timeoutInMinutes (<= 30)")
steps = job["steps"]
use = [s for s in steps if isinstance(s, dict) and s.get("task") == "UseDotNet@2"][0]
gj = __import__("json").loads((root / "global.json").read_text())["sdk"]
expect(str(use["inputs"]["version"]) == gj["version"], f"template SDK == global.json SDK ({gj['version']})")
expect(gj["rollForward"] == "disable", "global.json rollForward disabled")
pub = [s for s in steps if isinstance(s, dict) and "publish" in s]
expect(len(pub) == 1 and pub[0]["publish"] == "out/web" and pub[0]["artifact"] == "orders-api-web",
       "template: publishes out/web as artifact orders-api-web")
ifs = [s for s in steps if isinstance(s, dict) and any(k.startswith("${{ if") for k in s)]
expect(len(ifs) == 1 and "eq(parameters.publishPackages, true)" in list(ifs[0])[0],
       "template: feed push only behind publishPackages == true")
push = [s for s in ifs[0][list(ifs[0])[0]] if "bash" in s][0]
feed_urls = re.findall(r"https://pkgs\.dev\.azure\.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+/_packaging/[A-Za-z0-9._-]+/nuget/v3/index\.json", push["bash"])
expect(len(feed_urls) == 1, "feed URL is one project-scoped Azure Artifacts URL (org/project/_packaging/feed)")
expect("refs/heads/main" in push["condition"], "feed push also limited to refs/heads/main")
expect("ci/build.sh" in [s for s in steps if isinstance(s, dict) and "bash" in s][0]["bash"],
       "template runs ci/build.sh")
sys.exit(1 if failures else 0)
