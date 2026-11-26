"""The catalog generator and the track fetcher, checked with no network and no player.

A small ZIP is built in memory and served by a stand-in for the HTTP layer that honours
byte ranges the way the real servers were seen to.

    python3 -m unittest discover -s test
"""
import importlib.util, io, json, os, sys, tempfile, threading, unittest, zipfile, zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, os.path.join(ROOT, path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


catalog = load("build_catalog", "tools/build_catalog.py")
fetch = load("mood_fetch", "plugin/bin/mood_fetch.py")


def noise(n, seed):
    """Bytes that barely compress, like audio."""
    out, x = bytearray(), seed
    for _ in range(n):
        x = (x * 1103515245 + 12345) & 0x7FFFFFFF
        out.append((x >> 16) & 0xFF)
    return bytes(out)


TRACKS = {
    "calm/first-light.mp3": noise(40000, 1) + b"\x00" * 9000,
    "calm/second-wind.mp3": noise(70000, 2),
    "busy/third-rail.mp3": noise(30000, 3),
}


def make_zip(stored=()):
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as z:
        for name, data in TRACKS.items():
            z.writestr(zipfile.ZipInfo(name), data,
                       zipfile.ZIP_STORED if name in stored else zipfile.ZIP_DEFLATED)
    return buf.getvalue()


class Response:
    """Enough of an HTTP response for both tools."""

    def __init__(self, body, status=200, headers=None, cut=None):
        self.body, self.status, self.headers, self.pos = body, status, headers or {}, 0
        self.cut = cut

    def read(self, n=-1):
        end = len(self.body) if self.cut is None else min(len(self.body), self.cut)
        n = end - self.pos if n is None or n < 0 else min(n, end - self.pos)
        piece = self.body[self.pos:self.pos + n]
        self.pos += n
        return piece

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False


class Server:
    def __init__(self, files, ranges=True, cut=None):
        self.files, self.ranges, self.cut, self.requests = files, ranges, cut, []

    def open(self, url, start=None, end=None):
        self.requests.append((url, start, end))
        body = self.files[url]
        if start is None or not self.ranges:
            return Response(body, 200, {"Content-Length": str(len(body))}, self.cut)
        end = len(body) - 1 if end is None else end
        return Response(body[start:end + 1], 206, {"Content-Range": f"bytes {start}-{end}/{len(body)}"}, self.cut)

    def get(self, url, start=None, end=None):
        """The generator's fetch(): (body, headers)."""
        r = self.open(url, start, end)
        return r.read(), r.headers


ZIP_URL = "https://github.com/btahir/open-lofi/releases/download/v1.0.0/openlofi.zip"


def openlofi_server(archive):
    listing = {"name": "OpenLo-Fi", "categories": [{"slug": "calm", "label": "Calm & Quiet", "trackCount": 2},
                                                   {"slug": "busy", "label": "Busy", "trackCount": 1}],
               "tracks": [{"title": "First Light", "filename": "first-light.mp3", "category": "calm"},
                          {"title": "Second <b>Wind</b>", "filename": "second-wind.mp3", "category": "calm"},
                          {"title": "Third Rail", "filename": "third-rail.mp3", "category": "busy"}]}
    api = "https://api.github.com/repos/btahir/open-lofi"
    return Server({
        f"{api}/commits/main": json.dumps({"sha": "abc123"}).encode(),
        f"{api}/releases/tags/v1.0.0": json.dumps({"assets": [{"id": 9, "name": "openlofi.zip", "size": len(archive),
                                                               "updated_at": "2026-03-14T20:20:27Z", "digest": "sha256:00",
                                                               "browser_download_url": ZIP_URL}]}).encode(),
        "https://raw.githubusercontent.com/btahir/open-lofi/abc123/catalog.json": json.dumps(listing).encode(),
        ZIP_URL: archive,
    })


IA_META = {
    "metadata": {"title": "Somebody · Slow", "creator": "Somebody", "subject": ["Slow", "x"],
                 "licenseurl": "https://creativecommons.org/publicdomain/zero/1.0/", "uploader": "person@example.org"},
    "item_last_updated": 1792473632,
    "files": [
        {"name": "A Song.mp3", "source": "original", "size": "2000", "length": "131.95", "crc32": "C8DA0601", "title": "A Song"},
        {"name": "A Song.png", "source": "derivative", "size": "10"},
        {"name": "No Length.mp3", "source": "original", "size": "3000", "crc32": "00000001"},
    ],
}


class ZipIndex(unittest.TestCase):
    def test_index_matches_what_zipfile_wrote(self):
        archive = make_zip()
        index = catalog.parse_zip_index(archive[-4096:], len(archive))
        with zipfile.ZipFile(io.BytesIO(archive)) as z:
            for info in z.infolist():
                e = index[info.filename]
                self.assertEqual((e["header"], e["length"], e["size"], e["crc32"], e["method"]),
                                 (info.header_offset, info.compress_size, info.file_size, info.CRC, info.compress_type))

    def test_data_offset_is_past_the_header_name_and_extra_field(self):
        archive = make_zip()
        index = catalog.parse_zip_index(archive, len(archive))
        for name, e in index.items():
            start = catalog.local_data_offset(archive[e["header"]:e["header"] + 30 + len(name)], e["header"], name)
            raw = archive[start:start + e["length"]]
            self.assertEqual(zlib.decompressobj(-15).decompress(raw), TRACKS[name])

    def test_a_header_naming_another_file_is_refused(self):
        archive = make_zip()
        e = catalog.parse_zip_index(archive, len(archive))["calm/first-light.mp3"]
        with self.assertRaises(catalog.CatalogError):
            catalog.local_data_offset(archive[e["header"]:e["header"] + 60], e["header"], "calm/second-wind.mp3")

    def test_not_a_zip(self):
        with self.assertRaises(catalog.CatalogError):
            catalog.parse_zip_index(b"x" * 500, 500)


class Generator(unittest.TestCase):
    def test_open_lofi_tracks_point_into_the_archive(self):
        archive = make_zip()
        source, archives, cats, tracks = catalog.openlofi(openlofi_server(archive).get)
        self.assertEqual([t["id"] for t in tracks], ["open-lofi:calm:first-light", "open-lofi:calm:second-wind",
                                                     "open-lofi:busy:third-rail"])
        self.assertEqual(archives, [{"id": "open-lofi-v1.0.0", "url": ZIP_URL, "size": len(archive)}])
        self.assertEqual(source["revision"]["repositoryCommit"], "abc123")
        for t in tracks:
            loc = t["location"]
            data = zlib.decompressobj(-15).decompress(archive[loc["offset"]:loc["offset"] + loc["length"]])
            self.assertEqual(data, TRACKS[loc["name"]])
            self.assertEqual(loc["crc32"], f"{zlib.crc32(data):08x}")
            self.assertEqual(t["size"], len(data))
            self.assertIsNone(t["seconds"], "the collection gives no lengths")
        self.assertNotIn("<", tracks[1]["title"])

    def test_no_whole_archive_is_ever_requested(self):
        server = openlofi_server(make_zip())
        catalog.openlofi(server.get)
        for url, start, end in server.requests:
            if url == ZIP_URL:
                self.assertIsNotNone(start)
        asked = sum(end - start + 1 for url, start, end in server.requests if url == ZIP_URL)
        self.assertLess(asked, 70000, "only the index and the small headers")

    def test_internet_archive_item(self):
        source, cat, tracks = catalog.archive_item("somebody-slow", IA_META)
        self.assertEqual(cat, {"id": "slow", "source": "somebody-slow", "label": "Slow"})
        self.assertEqual([t["id"] for t in tracks], ["ia:somebody-slow:a-song", "ia:somebody-slow:no-length"])
        self.assertEqual(tracks[0]["location"], {"kind": "url", "crc32": "c8da0601",
                                                 "url": "https://archive.org/download/somebody-slow/A%20Song.mp3"})
        self.assertEqual((tracks[0]["seconds"], tracks[1]["seconds"]), (131.95, None))
        self.assertEqual(source["revision"], {"itemLastUpdated": 1792473632})
        self.assertNotIn("example.org", json.dumps([source, cat, tracks]), "the uploader's address is not copied")

    def test_an_item_that_is_not_cc0_is_refused(self):
        meta = json.loads(json.dumps(IA_META))
        meta["metadata"]["licenseurl"] = "https://creativecommons.org/licenses/by-nc/4.0/"
        with self.assertRaises(catalog.CatalogError):
            catalog.archive_item("somebody-slow", meta)

    def test_the_catalog_in_the_repo_is_valid_and_dump_round_trips(self):
        with open(os.path.join(ROOT, "catalog", "catalog.json"), encoding="utf-8") as f:
            text = f.read()
        with open(os.path.join(ROOT, "catalog", "categories.json"), encoding="utf-8") as f:
            names = json.load(f)
        doc = json.loads(text)
        summary = catalog.validate(doc, names)
        self.assertEqual((summary["tracks"], summary["categories"]), (451, 13))
        self.assertEqual(catalog.dump(doc), text, "the file is exactly what the generator writes")
        self.assertNotIn("@", text, "no addresses")

    def test_validation_catches_a_range_outside_the_archive(self):
        archive = make_zip()
        source, archives, cats, tracks = catalog.openlofi(openlofi_server(archive).get)
        for c in cats:
            c["tracks"] = sum(1 for t in tracks if t["category"] == c["id"])
        doc = {"version": 1, "sources": [source], "archives": archives, "categories": cats, "tracks": tracks}
        catalog.validate(doc)
        tracks[0]["location"]["length"] = len(archive)
        with self.assertRaises(catalog.CatalogError):
            catalog.validate(doc)


def zip_spec(archive, name, **over):
    index = catalog.parse_zip_index(archive, len(archive))
    e = index[name]
    offset = catalog.local_data_offset(archive[e["header"]:e["header"] + 30 + len(name)], e["header"], name)
    spec = {"kind": "zip", "url": ZIP_URL, "archive_size": len(archive), "name": name, "header": e["header"],
            "offset": offset, "length": e["length"], "method": e["method"], "crc32": f"{e['crc32']:08x}",
            "size": e["size"], "start": 0.0}
    spec.update(over)
    return spec


class Slice(unittest.TestCase):
    def test_a_track_comes_out_of_the_zip_whole_and_verified(self):
        archive = make_zip()
        server = Server({ZIP_URL: archive})
        for name, data in TRACKS.items():
            spec = zip_spec(archive, name)
            self.assertEqual(b"".join(fetch.track_zip(spec, server.open)), data)
            self.assertTrue(spec["verified"])
        self.assertEqual(len(server.requests), 3, "one request per track")
        for _, start, end in server.requests:
            self.assertLess(end - start, 80000)

    def test_a_stored_member_needs_no_unpacking(self):
        archive = make_zip(stored=("busy/third-rail.mp3",))
        spec = zip_spec(archive, "busy/third-rail.mp3")
        self.assertEqual(spec["method"], 0)
        self.assertEqual(b"".join(fetch.track_zip(spec, Server({ZIP_URL: archive}).open)), TRACKS["busy/third-rail.mp3"])

    def test_bytes_are_handed_on_as_they_arrive(self):
        archive = make_zip()
        pieces = list(fetch.track_zip(zip_spec(archive, "calm/second-wind.mp3"), Server({ZIP_URL: archive}).open))
        self.assertGreater(len(pieces), 1)

    def test_a_changed_archive_is_noticed_before_anything_is_played(self):
        archive = make_zip()
        spec = zip_spec(archive, "calm/first-light.mp3")
        grown = archive + b"extra"
        with self.assertRaises(fetch.FetchError) as cm:
            next(fetch.track_zip(dict(spec), Server({ZIP_URL: grown}).open))
        self.assertEqual(cm.exception.kind, "changed")
        other = dict(zip_spec(archive, "calm/second-wind.mp3"), name="calm/first-light.mp3")
        with self.assertRaises(fetch.FetchError) as cm:
            next(fetch.track_zip(other, Server({ZIP_URL: archive}).open))
        self.assertEqual(cm.exception.kind, "changed")

    def test_a_wrong_checksum_is_reported(self):
        archive = make_zip()
        spec = zip_spec(archive, "calm/first-light.mp3", crc32="deadbeef")
        with self.assertRaises(fetch.FetchError) as cm:
            list(fetch.track_zip(spec, Server({ZIP_URL: archive}).open))
        self.assertEqual(cm.exception.kind, "changed")

    def test_a_server_that_ignores_ranges_is_refused_rather_than_downloaded(self):
        archive = make_zip()
        with self.assertRaises(fetch.FetchError) as cm:
            next(fetch.track_zip(zip_spec(archive, "calm/first-light.mp3"), Server({ZIP_URL: archive}, ranges=False).open))
        self.assertEqual(cm.exception.kind, "source")

    def test_a_transfer_that_stops_short_is_offline_not_a_bad_source(self):
        archive = make_zip()
        with self.assertRaises(fetch.FetchError) as cm:
            list(fetch.track_zip(zip_spec(archive, "calm/second-wind.mp3"), Server({ZIP_URL: archive}, cut=20000).open))
        self.assertEqual(cm.exception.kind, "offline")

    def test_resuming_part_way_skips_the_start(self):
        archive = make_zip()
        name = "calm/second-wind.mp3"
        got = b"".join(fetch.track_zip(zip_spec(archive, name, start=0.5), Server({ZIP_URL: archive}).open))
        self.assertEqual(got, TRACKS[name][len(TRACKS[name]) // 2:])


class Direct(unittest.TestCase):
    URL = "https://archive.org/download/item/A%20Song.mp3"
    DATA = noise(90000, 7)

    def spec(self, **over):
        return dict({"kind": "url", "url": self.URL, "size": len(self.DATA),
                     "crc32": f"{zlib.crc32(self.DATA):08x}", "start": 0.0}, **over)

    def test_a_direct_link_is_fetched_whole_and_verified(self):
        spec, wire = self.spec(), [0]
        self.assertEqual(b"".join(fetch.track_url(spec, Server({self.URL: self.DATA}).open, wire)), self.DATA)
        self.assertTrue(spec["verified"])
        self.assertEqual(wire[0], len(self.DATA), "data used is the track and nothing more")

    def test_a_different_file_at_the_link_is_refused_up_front(self):
        with self.assertRaises(fetch.FetchError) as cm:
            next(fetch.track_url(self.spec(size=5), Server({self.URL: self.DATA}).open))
        self.assertEqual(cm.exception.kind, "changed")

    def test_a_file_that_runs_past_its_recorded_size_is_cut_off(self):
        class Endless(Server):
            def open(self, url, start=None, end=None):
                return Response(self.files[url], 200, {})          # no Content-Length to check
        with self.assertRaises(fetch.FetchError) as cm:
            list(fetch.track_url(self.spec(size=5000), Endless({self.URL: self.DATA}).open))
        self.assertEqual(cm.exception.kind, "changed")

    def test_same_size_wrong_bytes_is_flagged_unverified(self):
        spec = self.spec(crc32="deadbeef")
        list(fetch.track_url(spec, Server({self.URL: self.DATA}).open))
        self.assertFalse(spec["verified"])

    def test_resuming_asks_only_for_the_rest(self):
        server, wire = Server({self.URL: self.DATA}), [0]
        got = b"".join(fetch.track_url(self.spec(start=0.5), server.open, wire))
        self.assertEqual(got, self.DATA[45000:])
        self.assertEqual(server.requests, [(self.URL, 45000, None)])
        self.assertEqual(wire[0], 45000)

    def test_resuming_against_a_server_without_ranges_still_starts_in_the_right_place(self):
        got = b"".join(fetch.track_url(self.spec(start=0.5), Server({self.URL: self.DATA}, ranges=False).open))
        self.assertEqual(got, self.DATA[45000:])

    def test_a_short_transfer_is_offline(self):
        with self.assertRaises(fetch.FetchError) as cm:
            list(fetch.track_url(self.spec(), Server({self.URL: self.DATA}, cut=1000).open))
        self.assertEqual(cm.exception.kind, "offline")


class Failures(unittest.TestCase):
    def test_unreachable_is_offline_and_an_answer_with_an_error_is_the_source(self):
        import socket, urllib.error
        self.assertEqual(fetch.classify(urllib.error.URLError(socket.gaierror(-3, "name resolution")))[0], "offline")
        self.assertEqual(fetch.classify(urllib.error.URLError(OSError(101, "Network is unreachable")))[0], "offline")
        self.assertEqual(fetch.classify(TimeoutError())[0], "offline")
        self.assertEqual(fetch.classify(ConnectionResetError())[0], "offline")
        http = urllib.error.HTTPError("https://x", 404, "Not Found", {}, None)
        self.addCleanup(http.close)
        self.assertEqual(fetch.classify(http), ("source", "HTTP 404"))
        self.assertEqual(fetch.classify(fetch.FetchError("changed", "x")), ("changed", "x"))


class Pipe(unittest.TestCase):
    """run() end to end with a stand-in source and a reader standing in for the player."""

    def go(self, source, read=True):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "mood", "1.fifo")
            got, lines = [], []
            real_say = fetch.say
            fetch.say = lambda **m: lines.append(m)

            def reader():
                while not os.path.exists(path):
                    pass
                with open(path, "rb") as f:
                    got.append(f.read() if read else f.read(10))
            t = threading.Thread(target=reader)
            t.start()
            try:
                code = fetch.run({"kind": "url"}, path, analyze=False, source=source)
            finally:
                fetch.say = real_say
            t.join()
            return code, b"".join(got), lines, os.path.exists(path)

    def test_bytes_reach_the_reader_and_the_pipe_is_removed(self):
        data = [noise(50000, 1), noise(50000, 2)]
        code, got, lines, left = self.go(lambda spec: iter(data))
        self.assertEqual((code, got, left), (0, b"".join(data), False))
        self.assertEqual([m["ev"] for m in lines], ["ready", "first", "done"])
        self.assertEqual(lines[-1]["bytes"], 100000)
        self.assertGreaterEqual(lines[-1]["cost"]["peakKb"], 1000, "it says what it cost")

    def test_a_failure_part_way_is_reported_with_what_was_sent(self):
        def source(spec):
            yield b"x" * 1000
            raise fetch.FetchError("offline", "the transfer ended early")
        code, got, lines, left = self.go(source)
        self.assertEqual((code, got, left), (2, b"x" * 1000, False))
        self.assertEqual(lines[-1], {"ev": "error", "kind": "offline", "detail": "the transfer ended early", "bytes": 1000})

    def test_a_reader_that_walks_away_is_not_an_error(self):
        code, got, lines, left = self.go(lambda spec: iter([noise(200000, 3)] * 8), read=False)
        self.assertEqual((code, left), (0, False))
        self.assertNotIn("error", [m["ev"] for m in lines])


class Onsets(unittest.TestCase):
    def stats(self, levels):
        """ffmpeg's printed statistics for frames of [full, low, mid, high] dB."""
        out = []
        for n, row in enumerate(levels):
            out.append(f"frame:{n}    pts:{n * 882}    pts_time:{n * 0.04}")
            out += [f"lavfi.astats.{c + 1}.RMS_level={v}" for c, v in enumerate(row)]
        return out

    def test_levels_become_bytes_and_silence_is_zero(self):
        rows = list(fetch.frames_from_stats(self.stats([[-84, -90, "-inf", 0], [-42, -42, -42, -42]])))
        self.assertEqual([r[:4] for r in rows], [[0, 0, 0, 255], [128, 128, 128, 128]])

    def test_a_hit_in_steady_music_is_one_onset_on_the_right_frame(self):
        levels = [[-30, -30, -30, -30]] * 40 + [[-12, -12, -14, -20]] + [[-28, -28, -29, -30]] * 40
        rows = list(fetch.frames_from_stats(self.stats(levels)))
        self.assertEqual(len(rows), len(levels))
        self.assertEqual([i for i, r in enumerate(rows) if r[4]], [40])

    def test_steady_sound_and_a_slow_swell_are_not_onsets(self):
        steady = list(fetch.frames_from_stats(self.stats([[-25, -26, -27, -28]] * 100)))
        swell = list(fetch.frames_from_stats(self.stats([[-60 + i * 0.3] * 4 for i in range(100)])))
        self.assertFalse(any(r[4] for r in steady + swell))

    def test_a_beat_gives_about_one_onset_per_beat(self):
        levels = []
        for i in range(300):                      # twelve seconds at 120 bpm: a hit every 12.5 frames
            hit = i % 25 in (0, 12)
            levels.append([-10, -8, -14, -18] if hit else [-26, -30, -27, -28])
        rows = list(fetch.frames_from_stats(self.stats(levels)))
        count = sum(1 for r in rows if r[4])
        self.assertTrue(20 <= count <= 24, count)


if __name__ == "__main__":
    unittest.main()
