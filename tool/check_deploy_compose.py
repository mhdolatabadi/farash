"""Compare real Compose project/volume identities for normal and exported source."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
config = root / "deploy"


def resolved(source, env):
    return json.loads(subprocess.check_output([
        "docker", "compose", "--project-directory", str(config),
        "--env-file", str(config / ".env"), "-f", str(source / "compose.yaml"),
        "config", "--format", "json"], env=env, text=True))


with tempfile.TemporaryDirectory(prefix="farash exported release ") as temporary:
    release = Path(temporary) / "deploy"
    shutil.copytree(config, release, ignore=shutil.ignore_patterns(".env", "backups"))
    env = {**os.environ, "FARASH_IMAGE_TAG": "a" * 40}
    env.pop("FARASH_CADDYFILE", None)
    previous = resolved(config, env)
    current = resolved(release, {**env, "FARASH_CADDYFILE": str(release / "Caddyfile")})
    for key in ["name", "volumes", "networks"]:
        assert previous[key] == current[key], f"Compose {key} changed"
    for service in ["api", "web", "postgres"]:
        assert previous["services"][service] == current["services"][service], service
    volumes = current["services"]["caddy"]["volumes"]
    caddy = next(v for v in volumes if v["target"] == "/etc/caddy/Caddyfile")
    assert caddy["source"] == str(release / "Caddyfile")
    assert caddy["read_only"] is True
print("Exported deployment preserves Compose project, volumes and networks.")
