#!/usr/bin/env python3
"""Write the GitHub Actions matrix of bake targets that need building.

Targets come from `docker buildx bake --print`, so docker/docker-bake.hcl stays the only list.
Env: EVENT_NAME, BEFORE (push base commit), TARGETS (workflow_dispatch input), GITHUB_OUTPUT.
"""
import json
import os
import re
import subprocess

# A change to any of these rebuilds every image.
SHARED = re.compile(
    r"^(docker/docker-bake\.hcl|docker/smoke/.*|\.github/workflows/build-containers\.yml|\.github/scripts/bake_matrix\.py)$"
)


def bake_targets() -> dict:
    out = subprocess.run(
        ["docker", "buildx", "bake", "--print", "default"],
        cwd="docker", check=True, capture_output=True, text=True,
    ).stdout
    return json.loads(out)["target"]


def changed_files(before: str) -> list[str]:
    if not before or set(before) == {"0"}:
        return []  # new branch: no base to diff against
    try:
        out = subprocess.run(
            ["git", "diff", "--name-only", before, "HEAD"], check=True, capture_output=True, text=True
        ).stdout
    except subprocess.CalledProcessError:
        return []  # base commit missing after a force-push
    return out.split()


def select(targets: dict, event: str, before: str, requested: str) -> list[str]:
    if event == "workflow_dispatch":
        wanted = [t.strip() for t in requested.split(",") if t.strip()]
        if not wanted or wanted == ["all"]:
            return sorted(targets)
        unknown = set(wanted) - set(targets)
        if unknown:
            raise SystemExit(f"Unknown bake targets: {sorted(unknown)}")
        return wanted

    files = changed_files(before)
    if not files or any(SHARED.match(f) for f in files):
        return sorted(targets)

    selected = set()
    for f in files:
        # docker/Dockerfile.<tool>.dockerfile and docker/envs/<tool>-<backend>.yml belong to <tool>.
        m = re.match(r"^docker/(?:Dockerfile\.(.+)\.dockerfile|envs/([^/-]+)-[^/]+)$", f)
        if m:
            dockerfile = f"Dockerfile.{m.group(1) or m.group(2)}.dockerfile"
            selected |= {n for n, t in targets.items() if t["dockerfile"] == dockerfile}
    return sorted(selected)


def main() -> None:
    targets = bake_targets()
    names = select(
        targets,
        os.environ.get("EVENT_NAME", ""),
        os.environ.get("BEFORE", ""),
        os.environ.get("TARGETS", "all"),
    )
    matrix = {"include": [{"target": n, "image": targets[n]["tags"][0]} for n in names]}
    print(json.dumps(matrix, indent=2))
    with open(os.environ["GITHUB_OUTPUT"], "a") as fh:
        fh.write(f"matrix={json.dumps(matrix)}\n")
        fh.write(f"any={'true' if names else 'false'}\n")


if __name__ == "__main__":
    main()
