"""Read a .deb without dpkg: ar members, control fields, control and data tar members. Internal release tooling."""
import io
import subprocess
import tarfile


def ar_members(raw):
    if raw[:8] != b"!<arch>\n":
        raise ValueError("not an ar archive")
    out, i = [], 8
    while i + 60 <= len(raw):
        h = raw[i:i + 60]
        name = h[:16].decode().strip().rstrip("/")
        size = int(h[48:58].decode().strip())
        out.append((name, raw[i + 60:i + 60 + size]))
        i += 60 + size + (size & 1)
    return out


def open_tar(name, data):
    if name.endswith(".zst"):
        data = subprocess.run(["zstd", "-dc"], input=data, capture_output=True, check=True).stdout
        return tarfile.open(fileobj=io.BytesIO(data), mode="r:")
    return tarfile.open(fileobj=io.BytesIO(data), mode="r:*")


class Deb:
    def __init__(self, path):
        self.members = ar_members(open(path, "rb").read())
        self.names = [n for n, _ in self.members]
        self.control = open_tar(*next(m for m in self.members if m[0].startswith("control.tar")))
        self.data = open_tar(*next(m for m in self.members if m[0].startswith("data.tar")))

    def ctl(self, name):
        for n in ("./" + name, name):
            try:
                f = self.control.extractfile(n)
            except KeyError:
                continue
            return f.read() if f else None
        return None

    def field(self, key):
        for l in self.ctl("control").decode().splitlines():
            if l.startswith(key + ":"):
                return l.split(":", 1)[1].strip()
        return None

    def member(self, path):
        try:
            f = self.data.extractfile(path)
        except KeyError:
            return None
        return f.read() if f else None

    def entries(self):
        return [(m.name, m.mode, m.uid, m.gid, m.mtime, m.type, m.size) for m in self.data.getmembers()]
