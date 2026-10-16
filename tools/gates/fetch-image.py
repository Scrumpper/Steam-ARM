#!/usr/bin/env python3
"""Container image rootfs from Docker Hub, pinned by digest. Internal test tooling, never shipped.

fetch-image.py resolve IMAGE:TAG ARCH         print platform manifest digest (amd64, arm64)
fetch-image.py fetch IMAGE@DIGEST DEST        unpack layers into DEST (new folder); layer sha256 checked

Whiteouts applied, device nodes skipped, ownership dropped, modes kept; member paths that leave DEST refused."""
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile

REG = "https://registry-1.docker.io/v2"
ACCEPT = ["application/vnd.oci.image.index.v1+json", "application/vnd.docker.distribution.manifest.list.v2+json",
          "application/vnd.oci.image.manifest.v1+json", "application/vnd.docker.distribution.manifest.v2+json"]


def repo_of(image):
    return image if "/" in image else "library/" + image


def curl(args, out=None):
    cmd = ["curl", "-sSfL", "--retry", "3", "--proto", "=https", "--proto-redir", "=https"] + args
    if out:
        subprocess.run(cmd + ["-o", out], check=True)
        return None
    return subprocess.run(cmd, check=True, capture_output=True).stdout


def token(repo):
    u = "https://auth.docker.io/token?service=registry.docker.io&scope=repository:%s:pull" % repo
    return json.loads(curl([u]))["token"]


def manifest(repo, ref, tok):
    h = ["-H", "Authorization: Bearer " + tok]
    for a in ACCEPT:
        h += ["-H", "Accept: " + a]
    return json.loads(curl(h + ["%s/%s/manifests/%s" % (REG, repo, ref)]))


def resolve(image, arch):
    name, tag = image.rsplit(":", 1)
    repo = repo_of(name)
    tok = token(repo)
    m = manifest(repo, tag, tok)
    for e in m.get("manifests", []):
        p = e.get("platform", {})
        if p.get("os") == "linux" and p.get("architecture") == arch and p.get("variant", "v8" if arch == "arm64" else "") \
                in (("v8", "") if arch == "arm64" else ("",)):
            return e["digest"]
    sys.exit("%s: no linux/%s image" % (image, arch))


def safe_rm(p):
    if os.path.islink(p) or os.path.isfile(p):
        os.unlink(p)
    elif os.path.isdir(p):
        for d, _, _ in os.walk(p):
            os.chmod(d, 0o700)
        shutil.rmtree(p)


def inside(dest, rel):
    t = os.path.realpath(os.path.join(dest, rel))
    return os.path.commonpath([t, dest]) == dest


def unpack(path, dest):
    with tarfile.open(path, "r:*") as tf:
        keep = []
        for m in tf.getmembers():
            rel = os.path.normpath(m.name.lstrip("/"))
            if rel.startswith("..") or not inside(dest, os.path.dirname(rel) or "."):
                print("  refused: " + m.name, file=sys.stderr)
                continue
            base = os.path.basename(rel)
            if base == ".wh..wh..opq":
                d = os.path.join(dest, os.path.dirname(rel))
                if os.path.isdir(d) and not os.path.islink(d):
                    for e in os.listdir(d):
                        safe_rm(os.path.join(d, e))
                continue
            if base.startswith(".wh."):
                safe_rm(os.path.join(dest, os.path.dirname(rel), base[4:]))
                continue
            if m.ischr() or m.isblk() or m.isfifo():
                continue
            t = os.path.join(dest, rel)
            if (os.path.lexists(t) and not (m.isdir() and os.path.isdir(t) and not os.path.islink(t))):
                safe_rm(t)
            keep.append(m)

        def filt(m, d):
            n = tarfile.tar_filter(m, d)
            return n.replace(mode=m.mode, uid=None, gid=None, uname=None, gname=None, deep=False)
        tf.extractall(dest, members=keep, filter=filt)
    for d, _, _ in os.walk(dest):
        if not os.path.islink(d):
            st = os.lstat(d)
            if not st.st_mode & 0o200:
                os.chmod(d, st.st_mode | 0o200)


def fetch(ref, dest):
    name, dig = ref.split("@", 1)
    repo = repo_of(name)
    tok = token(repo)
    m = manifest(repo, dig, tok)
    if "layers" not in m:
        sys.exit("%s: digest is an index, not a platform manifest" % ref)
    dest = os.path.realpath(dest)
    os.makedirs(dest)
    tmp = tempfile.mkdtemp(prefix="sarm-layer.", dir=os.path.dirname(dest))
    try:
        for layer in m["layers"]:
            f = os.path.join(tmp, "layer")
            curl(["-H", "Authorization: Bearer " + tok, "%s/%s/blobs/%s" % (REG, repo, layer["digest"])], out=f)
            h = hashlib.sha256()
            with open(f, "rb") as fh:
                for b in iter(lambda: fh.read(1 << 20), b""):
                    h.update(b)
            if "sha256:" + h.hexdigest() != layer["digest"]:
                sys.exit("layer digest mismatch: " + layer["digest"])
            if "zstd" in layer.get("mediaType", ""):
                subprocess.run(["zstd", "-qdf", f, "-o", f + ".tar"], check=True)
                os.replace(f + ".tar", f)
            unpack(f, dest)
            os.unlink(f)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main(a):
    if len(a) == 3 and a[0] == "resolve":
        print(resolve(a[1], a[2]))
    elif len(a) == 3 and a[0] == "fetch":
        fetch(a[1], a[2])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
