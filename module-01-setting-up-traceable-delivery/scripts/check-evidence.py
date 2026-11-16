#!/usr/bin/env python3
"""Check release-evidence.md: shape, run separation, and no invented values.

Usage: python3 check-evidence.py <path-to-release-evidence.md>
       python3 check-evidence.py --self-test

Standard library only. Exit 0 = pass, 1 = violation.
"""
import re
import sys
from pathlib import Path

SECTION_A = "A. Pull request validation run"
SECTION_B = "B. Post-merge CI run"
SECTION_C = "C. Release run"
FIELDS_A = ["Pipeline", "Pull request", "Run ID",
            "Revision (full 40-character commit ID)", "Result", "Evidence read from"]
FIELDS_B = ["Pipeline", "Source branch", "Pull request", "Run ID",
            "Revision (full 40-character commit ID)", "Result", "Evidence read from"]
FIELDS_C = ["Pipeline", "Source branch", "Parameters", "Run ID",
            "Revision (full 40-character commit ID)",
            "Package (`Globomantics.Orders.Contracts`) version",
            "Artifact (`orders-api-web`)",
            "Deployment (`staging` environment history)"]
REV = "Revision (full 40-character commit ID)"


def parse(text):
    sections, current = {}, None
    for line in text.splitlines():
        m = re.match(r"^## (.+?)\s*(\(.*\))?\s*$", line)
        if m:
            current = m.group(1).strip()
            sections[current] = {}
            continue
        f = re.match(r"^- (.+?): (.*)$", line)
        if f and current:
            sections[current][f.group(1).strip()] = f.group(2).strip().strip("`")
    return sections


def check(text):
    errors = []
    sections = parse(text)
    named = []
    for label, prefix, fields in (("A", SECTION_A, FIELDS_A), ("B", SECTION_B, FIELDS_B),
                                  ("C", SECTION_C, FIELDS_C)):
        sec = next((v for k, v in sections.items() if k.startswith(prefix)), None)
        if sec is None:
            errors.append("missing section: " + prefix)
        named.append((label, sec, fields))
    if errors:
        return errors
    for name, sec, fields in named:
        for field in fields:
            if field not in sec:
                errors.append(f"section {name}: missing field '{field}'")
        for field, value in sec.items():
            if value == "":
                errors.append(f"section {name}: '{field}' is empty (use 'pending')")
        run = sec.get("Run ID", "pending")
        if run != "pending" and not re.fullmatch(r"[0-9]+", run):
            errors.append(f"section {name}: Run ID must be digits or 'pending', got '{run}'")
        rev = sec.get(REV, "pending")
        if rev != "pending" and not re.fullmatch(r"[0-9a-f]{40}", rev):
            errors.append(f"section {name}: revision must be 40 lowercase hex characters or 'pending'")
    seen = {}
    for name, sec, _ in named:
        run = sec.get("Run ID", "pending")
        if run == "pending":
            continue
        if run in seen:
            errors.append(f"sections {seen[run]} and {name} share Run ID {run}: "
                          "PR validation, post-merge CI and release must be different runs")
        seen[run] = name
    c = named[2][1]
    if c.get("Run ID", "pending") == "pending" and any(
            c.get(f, "pending") != "pending" for f in FIELDS_C[5:]):
        errors.append("section C has package/artifact/deployment values but no release Run ID")
    # The same revision can legitimately build in two runs; only run IDs must differ.
    return errors


SELF_OK = """# x
## A. Pull request validation run (v)
- Pipeline: `orders-api-ci`
- Pull request: pending
- Run ID: %s
- Revision (full 40-character commit ID): pending
- Result: pending
- Evidence read from: pending
## B. Post-merge CI run (c)
- Pipeline: `orders-api-ci`
- Source branch: `main`
- Pull request: pending
- Run ID: 4242
- Revision (full 40-character commit ID): %s
- Result: pending
- Evidence read from: pending
## C. Release run (r)
- Pipeline: `orders-api-ci`
- Source branch: `main`
- Parameters: pending
- Run ID: %s
- Revision (full 40-character commit ID): pending
- Package (`Globomantics.Orders.Contracts`) version: pending
- Artifact (`orders-api-web`): pending
- Deployment (`staging` environment history): pending
"""


def sample(a="pending", rev="pending", c="pending"):
    return SELF_OK % (a, rev, c)


def self_test():
    sha = "a" * 40
    cases = [
        ("pending template", sample().replace("4242", "pending"), True),
        ("B filled, A and C pending", sample(rev=sha), True),
        ("A, B, C all different runs", sample("4100", sha, "4300"), True),
        ("B and C same run ID", sample(rev=sha, c="4242"), False),
        ("A and B same run ID", sample(a="4242", rev=sha), False),
        ("short revision", sample(rev="abc123"), False),
        ("non-numeric run", sample(rev=sha).replace("4242", "run-4242"), False),
        ("empty value", sample(rev=sha).replace("Result: pending", "Result: "), False),
        ("missing section C", sample(rev=sha).split("## C.")[0], False),
        ("C package without run", sample(rev=sha).replace("version: pending", "version: 1.0.4300"), False),
    ]
    bad = 0
    for name, text, expect_ok in cases:
        ok = not check(text)
        flag = "ok " if ok == expect_ok else "BAD"
        print(f"{flag} self-test: {name} -> {'pass' if ok else 'fail'} (expected {'pass' if expect_ok else 'fail'})")
        bad += ok != expect_ok
    return 1 if bad else 0


def main(argv):
    if len(argv) == 2 and argv[1] == "--self-test":
        return self_test()
    if len(argv) != 2:
        print(__doc__)
        return 1
    errors = check(Path(argv[1]).read_text(encoding="utf-8"))
    for e in errors:
        print("FAIL:", e)
    if not errors:
        print("PASS: evidence index shape and run separation")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
