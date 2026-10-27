"""Verify exported deployment keeps identities and the shared-proxy contract."""
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
    previous = resolved(config, env)
    current = resolved(release, env)

    for key in ["name", "volumes", "networks"]:
        assert previous[key] == current[key], f"Compose {key} changed"
    for service in ["api", "web", "postgres"]:
        assert previous["services"][service] == current["services"][service], service

    assert current["name"] == "farash"
    assert "caddy" not in current["services"], "Farash must use the shared front proxy"

    proxy = current["networks"]["proxy"]
    assert proxy["external"] is True
    assert proxy["name"] == "proxynet"

    api = current["services"]["api"]
    web = current["services"]["web"]
    postgres = current["services"]["postgres"]
    assert api["container_name"] == "farash-api"
    assert web["container_name"] == "farash-web"
    assert set(api["networks"]) == {"internal", "proxy"}
    assert set(web["networks"]) == {"proxy"}
    assert set(postgres["networks"]) == {"internal"}

    for service in current["services"].values():
        assert not service.get("ports"), "Production services must not publish host ports"

    volume = current["volumes"]["postgres-data"]
    assert volume["name"] == "farash_postgres-data"

print("Exported deployment preserves the database and shared-proxy contract.")
