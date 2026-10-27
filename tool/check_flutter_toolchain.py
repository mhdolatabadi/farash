#!/usr/bin/env python3
"""Keep the production Flutter toolchain aligned across Docker and workflows."""

from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(1)


dockerfile = (ROOT / "deploy" / "Dockerfile.web").read_text()
ci = (ROOT / ".github" / "workflows" / "ci.yml").read_text()
release = (ROOT / ".github" / "workflows" / "android-release.yml").read_text()

if "cirruslabs/flutter" in dockerfile:
    fail("The retired cirruslabs/flutter image must not be used for production builds.")

version_match = re.search(r"^ARG FLUTTER_VERSION=([^\s]+)$", dockerfile, re.MULTILINE)
if not version_match:
    fail("deploy/Dockerfile.web must pin FLUTTER_VERSION.")
version = version_match.group(1)

sha_match = re.search(r"^ARG FLUTTER_SHA256=([0-9a-f]{64})$", dockerfile, re.MULTILINE)
if not sha_match:
    fail("deploy/Dockerfile.web must pin the official Flutter archive SHA-256.")

if "storage.googleapis.com/flutter_infra_release/releases/stable/linux/" not in dockerfile:
    fail("The web image must download Flutter from the official release archive.")

workflow_versions = re.findall(r"flutter-version:\s*['\"]?([^'\"\s]+)", ci + "\n" + release)
if len(workflow_versions) != 3:
    fail(f"Expected three pinned workflow Flutter versions, found {len(workflow_versions)}.")

mismatches = [item for item in workflow_versions if item != version]
if mismatches:
    fail(f"Workflow Flutter versions must all match Docker Flutter {version}: {workflow_versions}")

print(f"Flutter toolchain is aligned on {version}.")
