#!/usr/bin/env python3
"""Listen to the Open Lo-Fi collection one track at a time, without downloading it.

The collection is published as a single 554 MB ZIP. This script never fetches the whole
file. It reads the ZIP's index (the last 64 KB), then asks the server for only the bytes
of the track it is about to play, unpacks them in memory and hands them to mpv.

    tools/audition.py                list the categories
    tools/audition.py CATEGORY       play that category, shuffled (in mpv: q = next track)
    tools/audition.py --check [N]    fetch N tracks, verify them, print durations; plays nothing

Nothing is kept: each track lives in a temporary file under $XDG_RUNTIME_DIR (memory) only
while it plays. Needs Python 3 and, for playing, mpv; --check uses ffprobe when present.

This is a listening aid for choosing music, not the plugin's playback backend.
"""
import json, os, random, shutil, struct, subprocess, sys, tempfile, urllib.request, zlib

ZIP_URL = "https://github.com/btahir/open-lofi/releases/download/v1.0.0/openlofi.zip"
CATALOG_URL = "https://raw.githubusercontent.com/btahir/open-lofi/main/catalog.json"
AGENT = {"User-Agent": "mood-audition/0 (python-urllib)"}
INDEX_TAIL = 65536


def fetch(url, start=None, end=None):
    """GET url, or bytes start..end inclusive. The server refuses suffix ranges, so both ends are given."""
    headers = dict(AGENT)
    if start is not None:
        headers["Range"] = f"bytes={start}-{end}"
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=60) as r:
        if start is not None and r.status != 206:
            raise SystemExit(f"the server did not return a byte range (HTTP {r.status}); refusing to download the whole file")
        return r.read(), r.headers


def zip_index():
    """Map filename -> (local header offset, compressed size, uncompressed size, crc32, method)."""
    _, headers = fetch(ZIP_URL, 0, 0)
    size = int(headers["Content-Range"].rsplit("/", 1)[1])
    tail, _ = fetch(ZIP_URL, size - INDEX_TAIL, size - 1)
    eocd = tail.rfind(b"PK\x05\x06")
    if eocd < 0:
        raise SystemExit("no ZIP index found at the end of the file")
    count, cd_size, cd_offset = struct.unpack("<HII", tail[eocd + 10:eocd + 20])
    p = cd_offset - (size - len(tail))
    if p < 0:
        raise SystemExit("the ZIP index is larger than expected")
    entries = {}
    for _ in range(count):
        if tail[p:p + 4] != b"PK\x01\x02":
            raise SystemExit("unexpected data in the ZIP index")
        method, _t, _d, crc, csize, usize, nlen, elen, clen = struct.unpack("<HHHIIIHHH", tail[p + 10:p + 34])
        offset = struct.unpack("<I", tail[p + 42:p + 46])[0]
        name = tail[p + 46:p + 46 + nlen].decode("utf-8")
        entries[name] = (offset, csize, usize, crc, method)
        p += 46 + nlen + elen + clen
    return entries


def track_bytes(entry):
    """Fetch one track's bytes from inside the ZIP and return the unpacked, checksum-verified MP3."""
    offset, csize, usize, crc, method = entry
    # Local header: 30 bytes, then name and extra field of lengths only stated here.
    head, _ = fetch(ZIP_URL, offset, offset + 29)
    if head[:4] != b"PK\x03\x04":
        raise SystemExit("unexpected data at the track's position")
    nlen, elen = struct.unpack("<HH", head[26:30])
    start = offset + 30 + nlen + elen
    raw, _ = fetch(ZIP_URL, start, start + csize - 1)
    data = zlib.decompressobj(-15).decompress(raw) if method == 8 else raw
    if len(data) != usize or zlib.crc32(data) != crc:
        raise SystemExit("track failed its checksum")
    return data


def runtime_file(data):
    d = os.environ.get("XDG_RUNTIME_DIR") or tempfile.gettempdir()
    f = tempfile.NamedTemporaryFile(prefix="mood-audition-", suffix=".mp3", dir=d, delete=False)
    f.write(data)
    f.close()
    return f.name


def duration(path):
    if not shutil.which("ffprobe"):
        return None
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", path],
                         capture_output=True, text=True).stdout.strip()
    try:
        return float(out)
    except ValueError:
        return None


def main(argv):
    catalog = json.loads(fetch(CATALOG_URL)[0])
    cats = {c["slug"]: c for c in catalog["categories"]}
    if not argv:
        print(f"{catalog['name']}: {catalog['trackCount']} tracks, license {catalog['license']}\n")
        for c in catalog["categories"]:
            print(f"  {c['slug']:<18}{c['trackCount']:>3}  {c['label']}")
        print("\nplay one:  tools/audition.py CATEGORY")
        return 0
    index = zip_index()
    if argv[0] == "--check":
        n = int(argv[1]) if len(argv) > 1 else 2
        total = 0
        for t in random.sample(catalog["tracks"], n):
            data = track_bytes(index[t["filename"]])
            path = runtime_file(data)
            try:
                secs = duration(path)
            finally:
                os.unlink(path)
            total += len(data)
            length = f"{int(secs // 60)}:{int(secs % 60):02d}" if secs else "length unknown"
            print(f"ok  {t['category']:<18}{t['title']:<34}{len(data) / 1e6:5.2f} MB  {length}")
        print(f"\n{n} tracks, {total / 1e6:.1f} MB fetched of a 554 MB collection; checksums match; nothing kept")
        return 0
    if argv[0] not in cats:
        raise SystemExit(f"no category '{argv[0]}'. Run with no arguments to list them.")
    if not shutil.which("mpv"):
        raise SystemExit("mpv is needed to play")
    tracks = [t for t in catalog["tracks"] if t["category"] == argv[0]]
    random.shuffle(tracks)
    print(f"{cats[argv[0]]['label']}: {len(tracks)} tracks. In mpv: q = next track, space = pause. Ctrl+C here stops.\n")
    for t in tracks:
        print(f"  {t['title']}")
        path = runtime_file(track_bytes(index[t["filename"]]))
        try:
            subprocess.run(["mpv", "--no-video", "--really-quiet", path])
        finally:
            os.unlink(path)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except KeyboardInterrupt:
        sys.exit(130)
