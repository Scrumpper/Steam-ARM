#!/bin/bash
# Fetch debian:<tag> amd64 rootfs from Docker Hub into SARM_TOOLS_DIR (default ~/.cache/sarm-tools)/<tag>-rootfs
# (dpkg-deb and amd64 apt system in a rootless chroot).
set -e
TAG=${1:-trixie-slim}; D=${SARM_TOOLS_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/sarm-tools}; R=$D/$TAG-rootfs
[ -x "$R/usr/bin/dpkg-deb" ] && { echo "$R"; exit 0; }
tok=$(curl -sSf "https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/debian:pull" | python3 -c 'import json,sys; print(json.load(sys.stdin)["token"])')
api=https://registry-1.docker.io/v2/library/debian
idx=$(curl -sSf -H "Authorization: Bearer $tok" -H "Accept: application/vnd.oci.image.index.v1+json" -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json" "$api/manifests/$TAG")
dig=$(python3 -c 'import json,sys; print([m["digest"] for m in json.loads(sys.argv[1])["manifests"] if m["platform"]["architecture"] == "amd64"][0])' "$idx")
man=$(curl -sSf -H "Authorization: Bearer $tok" -H "Accept: application/vnd.oci.image.manifest.v1+json" -H "Accept: application/vnd.docker.distribution.manifest.v2+json" "$api/manifests/$dig")
rm -rf "$R"; mkdir -p "$R"
for l in $(python3 -c 'import json,sys; print(" ".join(x["digest"] for x in json.loads(sys.argv[1])["layers"]))' "$man"); do
  curl -sSfL -H "Authorization: Bearer $tok" "$api/blobs/$l" -o "$D/layer.tgz"
  echo "$l" | grep -q "$(sha256sum "$D/layer.tgz" | cut -d' ' -f1)" || { echo "layer digest mismatch" >&2; exit 1; }
  tar -xzf "$D/layer.tgz" -C "$R" --no-same-owner 2>/dev/null || true
done
rm -f "$D/layer.tgz"
echo "$R"
