#!/usr/bin/env python3
"""Build catalog/catalog.json, the plugin's list of pointers to tracks.

No audio is downloaded. The script reads each collection's own metadata and writes, for
every track, where its bytes are and what is known about it:

  Open Lo-Fi        the repository's catalog.json, the index at the end of the release
                    ZIP, and each track's 30-byte header inside the ZIP (to learn where
                    its data starts). A track is a byte range inside that one file.
  Internet Archive  the metadata API for each item. A track is a direct link.

    tools/build_catalog.py            fetch the metadata and rewrite catalog/catalog.json
    tools/build_catalog.py --check    validate the catalog already in the repo; no network

Standard library only. Requests carry a generic client name and nothing personal.
Category display names are not written here; they live in catalog/categories.json.
"""
import argparse, datetime, json, os, re, struct, sys, urllib.parse, urllib.request

AGENT = "mood-catalog/1 (python-urllib)"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "catalog", "catalog.json")
CATEGORIES = os.path.join(ROOT, "catalog", "categories.json")

OPENLOFI_REPO = "btahir/open-lofi"
OPENLOFI_TAG = "v1.0.0"
OPENLOFI_ASSET = "openlofi.zip"
IA_ITEMS = ["alecpennradio-lofi", "alecpennradio-neo-classical", "alecpennradio-psychedelic-jazz"]
CC0 = "https://creativecommons.org/publicdomain/zero/1.0/"
INDEX_TAIL = 65536
MAX_TITLE = 120


class CatalogError(Exception):
    pass


def fetch(url, start=None, end=None):
    """GET url, or bytes start..end inclusive. Returns (body, headers)."""
    headers = {"User-Agent": AGENT}
    if start is not None:
        headers["Range"] = f"bytes={start}-{end}"
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=60) as r:
        if start is not None and r.status != 206:
            raise CatalogError(f"{url}: no byte range (HTTP {r.status}); refusing the whole file")
        return r.read(), r.headers


def slug(text):
    s = re.sub(r"[^a-z0-9]+", "-", str(text).lower()).strip("-")
    if not s:
        raise CatalogError(f"cannot make an id from {text!r}")
    return s


def clean(text, limit=MAX_TITLE):
    """One line of plain text: no control characters, no markup brackets, bounded."""
    s = re.sub(r"[\x00-\x1f\x7f‪-‮⁦-⁩]", " ", str(text))
    s = s.replace("<", "‹").replace(">", "›")
    return re.sub(r"\s+", " ", s).strip()[:limit]


# ---- ZIP ---------------------------------------------------------------------------

def parse_zip_index(tail, size):
    """Read the central directory out of the last bytes of a ZIP of `size` bytes.

    Returns {name: {"header": offset of the local header, "length": compressed size,
    "size": uncompressed size, "crc32": int, "method": int}}.
    """
    eocd = tail.rfind(b"PK\x05\x06")
    if eocd < 0:
        raise CatalogError("no ZIP index at the end of the file")
    count, cd_size, cd_offset = struct.unpack("<HII", tail[eocd + 10:eocd + 20])
    if cd_offset == 0xFFFFFFFF or count == 0xFFFF:
        raise CatalogError("ZIP64 archives are not supported")
    p = cd_offset - (size - len(tail))
    if p < 0:
        raise CatalogError("the ZIP index is larger than the bytes fetched")
    entries = {}
    for _ in range(count):
        if tail[p:p + 4] != b"PK\x01\x02":
            raise CatalogError("unexpected data in the ZIP index")
        flags, method, _t, _d, crc, csize, usize, nlen, elen, clen = struct.unpack("<HHHHIIIHHH", tail[p + 8:p + 34])
        offset = struct.unpack("<I", tail[p + 42:p + 46])[0]
        name = tail[p + 46:p + 46 + nlen].decode("utf-8")
        if flags & 1:
            raise CatalogError(f"{name}: encrypted entries are not supported")
        entries[name] = {"header": offset, "length": csize, "size": usize, "crc32": crc, "method": method}
        p += 46 + nlen + elen + clen
    return entries


def local_data_offset(header, offset, name):
    """Where an entry's data starts, from its local header (30 bytes plus the name)."""
    if header[:4] != b"PK\x03\x04":
        raise CatalogError(f"{name}: no local header at {offset}")
    nlen, elen = struct.unpack("<HH", header[26:30])
    found = header[30:30 + nlen].decode("utf-8", "replace")
    if len(header) >= 30 + nlen and found != name:
        raise CatalogError(f"{name}: the local header names {found!r}")
    return offset + 30 + nlen + elen


def zip_index(url, get=fetch):
    _, headers = get(url, 0, 0)
    size = int(headers["Content-Range"].rsplit("/", 1)[1])
    tail_len = min(INDEX_TAIL, size)
    tail, _ = get(url, size - tail_len, size - 1)
    return size, parse_zip_index(tail, size)


# ---- Open Lo-Fi --------------------------------------------------------------------

def openlofi(get=fetch, log=lambda m: None):
    api = f"https://api.github.com/repos/{OPENLOFI_REPO}"
    commit = json.loads(get(f"{api}/commits/main")[0])["sha"]
    release = json.loads(get(f"{api}/releases/tags/{OPENLOFI_TAG}")[0])
    asset = next(a for a in release["assets"] if a["name"] == OPENLOFI_ASSET)
    listing = json.loads(get(f"https://raw.githubusercontent.com/{OPENLOFI_REPO}/{commit}/catalog.json")[0])
    url = asset["browser_download_url"]
    size, index = zip_index(url, get)
    if size != asset["size"]:
        raise CatalogError(f"the ZIP is {size} bytes but the release says {asset['size']}")
    by_base = {}
    for name in index:
        by_base.setdefault(name.rsplit("/", 1)[-1], []).append(name)
    archive_id = f"open-lofi-{OPENLOFI_TAG}"
    page = f"https://github.com/{OPENLOFI_REPO}"
    tracks, seen = [], set()
    for n, t in enumerate(listing["tracks"]):
        names = by_base.get(t["filename"], [])
        want = f"{t['category']}/{t['filename']}"
        name = want if want in index else (names[0] if len(names) == 1 else None)
        if name is None:
            raise CatalogError(f"{t['filename']}: not found exactly once in the ZIP index")
        e = index[name]
        if e["method"] not in (0, 8):
            raise CatalogError(f"{name}: compression method {e['method']} is not supported")
        head, _ = get(url, e["header"], e["header"] + 30 + len(name.encode()) + 4)
        tid = f"open-lofi:{slug(t['category'])}:{slug(t['filename'].rsplit('.', 1)[0])}"
        if tid in seen:
            raise CatalogError(f"duplicate id {tid}")
        seen.add(tid)
        tracks.append({
            "id": tid, "category": slug(t["category"]), "title": clean(t["title"]),
            "creator": "Open Lo-Fi (btahir)", "page": page, "license": "CC0-1.0",
            "location": {"kind": "zip", "archive": archive_id, "name": name, "header": e["header"],
                         "offset": local_data_offset(head, e["header"], name), "length": e["length"],
                         "method": e["method"], "crc32": f"{e['crc32']:08x}"},
            "size": e["size"], "seconds": None,
        })
        if n % 20 == 0:
            log(f"open-lofi: {n + 1}/{len(listing['tracks'])} headers read")
    source = {
        "id": "open-lofi", "name": clean(listing.get("name", "Open Lo-Fi")), "creator": "btahir", "page": page,
        "license": "CC0-1.0", "licenseUrl": CC0,
        "licenseNote": "Stated once for the whole collection in the repository's README and catalog.",
        "revision": {"repositoryCommit": commit, "release": OPENLOFI_TAG, "assetId": asset["id"],
                     "assetUpdated": asset["updated_at"], "assetDigest": asset.get("digest")},
    }
    archive = {"id": archive_id, "url": url, "size": size}
    cats = [{"id": slug(c["slug"]), "source": "open-lofi", "label": clean(c["label"])} for c in listing["categories"]]
    return source, [archive], cats, tracks


# ---- Internet Archive --------------------------------------------------------------

def archive_item(item, meta):
    """Tracks from one Internet Archive item's metadata (already parsed JSON)."""
    md = meta["metadata"]
    if md.get("licenseurl") != CC0:
        raise CatalogError(f"{item}: license is {md.get('licenseurl')!r}, not CC0")
    subjects = md.get("subject") or []
    label = clean(subjects[0] if isinstance(subjects, list) and subjects else md["title"])
    cat = slug(label)
    creator = clean(md.get("creator", ""))
    page = f"https://archive.org/details/{item}"
    tracks, seen = [], set()
    for f in meta["files"]:
        if f.get("source") != "original" or not f["name"].lower().endswith(".mp3"):
            continue
        tid = f"ia:{item}:{slug(f['name'].rsplit('.', 1)[0])}"
        if tid in seen:
            raise CatalogError(f"duplicate id {tid}")
        seen.add(tid)
        try:
            seconds = round(float(f["length"]), 2)
        except (KeyError, ValueError):
            seconds = None
        tracks.append({
            "id": tid, "category": cat, "title": clean(f.get("title") or f["name"].rsplit(".", 1)[0]),
            "creator": clean(f.get("creator") or creator), "page": page, "license": "CC0-1.0",
            "location": {"kind": "url", "url": f"https://archive.org/download/{item}/{urllib.parse.quote(f['name'])}",
                         "crc32": f["crc32"].lower()},
            "size": int(f["size"]), "seconds": seconds,
        })
    # The uploader's address is in the item metadata; it is deliberately not copied.
    source = {
        "id": item, "name": clean(md["title"]), "creator": creator, "page": page,
        "license": "CC0-1.0", "licenseUrl": CC0,
        "licenseNote": "Chosen by the uploader on the Internet Archive item; the uploading account carries the creator's name.",
        "revision": {"itemLastUpdated": meta.get("item_last_updated")},
    }
    return source, {"id": cat, "source": item, "label": label}, tracks


# ---- assemble, validate, write -----------------------------------------------------

def build(get=fetch, log=lambda m: None, today=None):
    sources, archives, categories, tracks = [], [], [], []
    s, a, c, t = openlofi(get, log)
    sources.append(s); archives += a; categories += c; tracks += t
    for item in IA_ITEMS:
        meta = json.loads(get(f"https://archive.org/metadata/{item}")[0])
        s, c, t = archive_item(item, meta)
        sources.append(s); categories.append(c); tracks += t
        log(f"{item}: {len(t)} tracks")
    counts = {}
    for t in tracks:
        counts[t["category"]] = counts.get(t["category"], 0) + 1
    for c in categories:
        c["tracks"] = counts.get(c["id"], 0)
    catalog = {
        "version": 1,
        "generated": today or datetime.date.today().isoformat(),
        "generator": "tools/build_catalog.py",
        "note": "Pointers only: no audio is stored. Regenerate rather than edit by hand.",
        "sources": sources, "archives": archives, "categories": categories, "tracks": tracks,
    }
    validate(catalog)
    return catalog


def validate(catalog, categories_file=None):
    """Raise CatalogError unless the catalog is internally consistent. Returns a summary."""
    if catalog.get("version") != 1:
        raise CatalogError("unknown catalog version")
    sources = {s["id"] for s in catalog["sources"]}
    archives = {a["id"]: a for a in catalog["archives"]}
    cats = {c["id"]: c for c in catalog["categories"]}
    if len(cats) != len(catalog["categories"]):
        raise CatalogError("duplicate category id")
    ids, counts = set(), {}
    for t in catalog["tracks"]:
        for key in ("id", "category", "title", "creator", "page", "license", "location", "size"):
            if t.get(key) in (None, ""):
                raise CatalogError(f"{t.get('id')}: missing {key}")
        if t["id"] in ids:
            raise CatalogError(f"duplicate track id {t['id']}")
        ids.add(t["id"])
        if t["category"] not in cats:
            raise CatalogError(f"{t['id']}: unknown category {t['category']}")
        if re.search(r"[<>\x00-\x1f]", t["title"] + t["creator"]):
            raise CatalogError(f"{t['id']}: markup or control characters in its text")
        if not t["page"].startswith("https://"):
            raise CatalogError(f"{t['id']}: the source page is not https")
        loc = t["location"]
        if not re.fullmatch(r"[0-9a-f]{8}", loc.get("crc32", "")):
            raise CatalogError(f"{t['id']}: bad checksum")
        if loc["kind"] == "url":
            if not loc["url"].startswith("https://"):
                raise CatalogError(f"{t['id']}: the link is not https")
        elif loc["kind"] == "zip":
            a = archives.get(loc["archive"])
            if not a:
                raise CatalogError(f"{t['id']}: unknown archive {loc['archive']}")
            if not (0 <= loc["header"] < loc["offset"] and loc["offset"] + loc["length"] <= a["size"]):
                raise CatalogError(f"{t['id']}: its range is outside the archive")
            if loc["method"] not in (0, 8):
                raise CatalogError(f"{t['id']}: unsupported compression")
        else:
            raise CatalogError(f"{t['id']}: unknown location kind {loc['kind']}")
        if not (0 < t["size"] < 64 * 1024 * 1024):
            raise CatalogError(f"{t['id']}: implausible size")
        if t.get("seconds") is not None and not (1 <= t["seconds"] <= 3600):
            raise CatalogError(f"{t['id']}: implausible length")
        counts[t["category"]] = counts.get(t["category"], 0) + 1
    for c in catalog["categories"]:
        if c["source"] not in sources:
            raise CatalogError(f"category {c['id']}: unknown source")
        if counts.get(c["id"], 0) != c["tracks"] or c["tracks"] == 0:
            raise CatalogError(f"category {c['id']}: track count does not match")
    for a in archives.values():
        if not a["url"].startswith("https://"):
            raise CatalogError(f"archive {a['id']}: not https")
    if categories_file is not None:
        names, order = categories_file.get("names", {}), categories_file.get("order", [])
        if sorted(order) != sorted(cats):
            raise CatalogError("catalog/categories.json: 'order' must list every category exactly once")
        for cid in cats:
            if not names.get(cid) or re.search(r"[<>\x00-\x1f]", names[cid]) or len(names[cid]) > 24:
                raise CatalogError(f"catalog/categories.json: no usable display name for {cid}")
    return {"tracks": len(ids), "categories": len(cats), "bytes": sum(t["size"] for t in catalog["tracks"])}


def dump(catalog):
    """JSON with one track per line, so a regenerated catalog diffs line by line."""
    def block(key, value, last=False):
        return f'  {json.dumps(key)}: {json.dumps(value, ensure_ascii=False)}' + ("" if last else ",")
    def rows(key, items, last=False):
        body = ",\n".join("    " + json.dumps(i, ensure_ascii=False) for i in items)
        return f'  {json.dumps(key)}: [\n{body}\n  ]' + ("" if last else ",")
    out = ["{"]
    for key in ("version", "generated", "generator", "note"):
        out.append(block(key, catalog[key]))
    for key in ("sources", "archives", "categories"):
        out.append(rows(key, catalog[key]))
    out.append(rows("tracks", catalog["tracks"], last=True))
    out.append("}")
    return "\n".join(out) + "\n"


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--check", action="store_true", help="validate the catalog in the repo; no network")
    ap.add_argument("--out", default=CATALOG)
    args = ap.parse_args(argv)
    try:
        if args.check:
            with open(args.out, encoding="utf-8") as f:
                catalog = json.load(f)
            with open(CATEGORIES, encoding="utf-8") as f:
                summary = validate(catalog, json.load(f))
            print(f"ok: {summary['tracks']} tracks in {summary['categories']} categories, "
                  f"{summary['bytes'] / 1e6:.0f} MB of audio pointed at, generated {catalog['generated']}")
            return 0
        catalog = build(log=lambda m: print(m, file=sys.stderr))
        os.makedirs(os.path.dirname(args.out), exist_ok=True)
        with open(args.out, "w", encoding="utf-8") as f:
            f.write(dump(catalog))
        print(f"wrote {args.out}: {len(catalog['tracks'])} tracks in {len(catalog['categories'])} categories")
        return 0
    except CatalogError as e:
        print(f"build_catalog: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
