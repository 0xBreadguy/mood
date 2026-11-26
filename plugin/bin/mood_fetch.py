#!/usr/bin/env python3
"""Fetch one track and hand it to the player as it arrives. Keeps nothing.

The plugin's service runs this once per track. It writes the track's MP3 bytes into a
named pipe the player reads, and, when asked, sends the same bytes through ffmpeg once to
measure loudness, three frequency bands and onsets for the bar's visual.

A track's location is one of two kinds:

    url   a direct link (Internet Archive). One GET; redirects are followed.
    zip   a byte range inside a published ZIP (Open Lo-Fi). One ranged GET; the bytes are
          deflated, so they are unpacked as they arrive.

It talks to the service in JSON lines on stdout:

    {"ev":"ready"}                         the pipe exists; the player may open it
    {"ev":"first","ms":412}                the first audio bytes went to the player
    {"ev":"features","i":0,"hop":0.04,"frames":[[loud,low,mid,high,onset],...]}
    {"ev":"nofeatures","why":"..."}        the visual should go calm, not guess
    {"ev":"done","bytes":N,"wire":M,"verified":true}
    {"ev":"error","kind":"offline|source|changed|player","detail":"..."}

Standard library only. Requests carry a generic client name and nothing personal.
"""
import argparse, collections, errno, json, os, queue, resource, shutil, signal, socket, stat, struct, subprocess
import sys, threading, time, urllib.error, urllib.request, zlib

AGENT = "mood/1 (python-urllib)"
TIMEOUT = 12            # seconds to connect, and the longest silence tolerated mid-transfer
OPEN_WAIT = 15          # seconds for the player to open the pipe
CHUNK = 32 * 1024
HOP = 0.04              # one feature frame per 40 ms: 25 Hz
RATE = 22050
FRAME = int(RATE * HOP)
BATCH = 125             # frames per message: five seconds of music
EXIT = {"offline": 2, "source": 3, "changed": 3, "player": 4}

_out_lock = threading.Lock()


def say(**msg):
    with _out_lock:
        try:
            sys.stdout.write(json.dumps(msg, separators=(",", ":")) + "\n")
            sys.stdout.flush()
        except (BrokenPipeError, ValueError):
            pass


class FetchError(Exception):
    def __init__(self, kind, detail):
        super().__init__(detail)
        self.kind, self.detail = kind, detail


def classify(exc):
    """Sort a failure into 'offline' (cannot reach anything) or 'source' (it answered badly)."""
    if isinstance(exc, FetchError):
        return exc.kind, exc.detail
    if isinstance(exc, urllib.error.HTTPError):
        return "source", f"HTTP {exc.code}"
    reason = getattr(exc, "reason", exc)
    if isinstance(reason, (socket.gaierror, TimeoutError, socket.timeout, ConnectionError)):
        return "offline", type(reason).__name__
    if isinstance(reason, OSError) and reason.errno in (errno.ENETUNREACH, errno.EHOSTUNREACH, errno.ENETDOWN,
                                                        errno.ECONNREFUSED, errno.ETIMEDOUT, errno.ECONNRESET):
        return "offline", errno.errorcode.get(reason.errno, "network")
    if isinstance(exc, (urllib.error.URLError, OSError, EOFError)):
        return "offline", str(reason)[:80]
    return "source", f"{type(exc).__name__}: {exc}"[:120]


def http_open(url, start=None, end=None):
    headers = {"User-Agent": AGENT, "Accept": "*/*"}
    if start is not None:
        headers["Range"] = f"bytes={start}-{'' if end is None else end}"
    return urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=TIMEOUT)


def content_range(resp):
    """(start, end, total) from a 206 response, or None."""
    value = resp.headers.get("Content-Range", "")
    try:
        unit, rest = value.split(" ", 1)
        span, total = rest.split("/", 1)
        first, last = span.split("-", 1)
        return int(first), int(last), int(total)
    except ValueError:
        return None


def read_exact(resp, n):
    data = b""
    while len(data) < n:
        piece = resp.read(n - len(data))
        if not piece:
            raise FetchError("offline", "connection closed early")
        data += piece
    return data


def track_url(spec, opener=http_open, counter=None):
    """Yield a direct link's bytes. With a start fraction, ask only for the tail."""
    size, skip = spec["size"], int(spec["size"] * spec.get("start", 0.0))
    resp = opener(spec["url"], skip, None) if skip else opener(spec["url"])
    with resp:
        if skip and resp.status == 206:
            got = content_range(resp)
            if not got or got[0] != skip or got[2] != size:
                raise FetchError("changed", "the file is not the size the catalog recorded")
            drop = 0
        else:
            length = resp.headers.get("Content-Length")
            if length is not None and int(length) != size:
                raise FetchError("changed", "the file is not the size the catalog recorded")
            drop = skip
        crc, total = 0, 0
        while True:
            piece = resp.read(CHUNK)
            if not piece:
                break
            if counter is not None:
                counter[0] += len(piece)
            crc = zlib.crc32(piece, crc)
            total += len(piece)
            # A server that sent no length could otherwise send without end.
            if total > size:
                raise FetchError("changed", "the file is larger than the catalog recorded")
            if drop:
                cut = min(drop, len(piece))
                drop -= cut
                piece = piece[cut:]
            if piece:
                yield piece
        if not skip:
            if total != size:
                raise FetchError("offline", "the transfer ended early")
            spec["verified"] = f"{crc:08x}" == spec.get("crc32")


def track_zip(spec, opener=http_open, counter=None):
    """Yield one ZIP member's bytes, unpacked as they arrive and checked against the index."""
    header, offset, length = spec["header"], spec["offset"], spec["length"]
    with opener(spec["url"], header, offset + length - 1) as resp:
        got = content_range(resp)
        if resp.status != 206 or not got:
            raise FetchError("source", "the server did not return a byte range")
        if got[0] != header or got[2] != spec["archive_size"]:
            raise FetchError("changed", "the archive is not the one the catalog indexed")
        head = read_exact(resp, offset - header)
        nlen = struct.unpack("<H", head[26:28])[0] if len(head) >= 30 else 0
        if head[:4] != b"PK\x03\x04" or head[30:30 + nlen].decode("utf-8", "replace") != spec["name"]:
            raise FetchError("changed", "the archive is not the one the catalog indexed")
        if counter is not None:
            counter[0] += len(head)
        inflate = zlib.decompressobj(-15) if spec["method"] == 8 else None
        drop = int(spec["size"] * spec.get("start", 0.0))
        crc, total, left = 0, 0, length
        while left:
            piece = resp.read(min(CHUNK, left))
            if not piece:
                raise FetchError("offline", "the transfer ended early")
            left -= len(piece)
            if counter is not None:
                counter[0] += len(piece)
            try:
                data = inflate.decompress(piece) if inflate else piece
            except zlib.error:
                raise FetchError("changed", "the archive's bytes would not unpack")
            crc = zlib.crc32(data, crc)
            total += len(data)
            if drop:
                cut = min(drop, len(data))
                drop -= cut
                data = data[cut:]
            if data:
                yield data
        if inflate:
            tail = inflate.flush()
            crc = zlib.crc32(tail, crc)
            total += len(tail)
            if tail and not drop:
                yield tail
        if total != spec["size"] or f"{crc:08x}" != spec["crc32"]:
            raise FetchError("changed", "the track failed its checksum")
        spec["verified"] = True


# ---- features ----------------------------------------------------------------------

def quantize(db):
    """A level in dBFS as a byte: 0 is -84 dB or quieter, 255 is full scale."""
    if db != db or db < -84.0:
        return 0
    return min(255, int(round((db + 84.0) / 84.0 * 255)))


class Onsets:
    """Mark the frames where the music starts something: a note, a hit, a chord.

    Each frame's rise in level, summed over three bands, is compared with the last
    second's average rise. A frame that stands clear of it, and of its neighbours, is an
    onset. The answer for a frame is known one frame later.
    """
    FLOOR = -66.0

    def __init__(self):
        self.prev = None
        self.recent = collections.deque(maxlen=25)
        self.novelty = collections.deque([0.0, 0.0], maxlen=3)
        self.since = 99

    def push(self, bands):
        """Give this frame's band levels in dB. Returns the previous frame's onset strength, 0-255."""
        cur = [max(self.FLOOR, b) for b in bands]
        rise = 0.0
        if self.prev is not None:
            rise = sum(max(0.0, c - p) for c, p in zip(cur, self.prev))
        self.prev = cur
        mean = sum(self.recent) / len(self.recent) if self.recent else 0.0
        self.recent.append(rise)
        self.novelty.append(max(0.0, rise - 1.5 * mean - 3.0))
        before, mid, after = self.novelty
        self.since += 1
        if mid > 0.0 and mid >= before and mid > after and self.since >= 3:
            self.since = 0
            return max(1, min(255, int(round(mid / 24.0 * 255))))
        return 0


def frames_from_stats(lines):
    """Turn ffmpeg's printed per-frame statistics into [loud, low, mid, high, onset] rows."""
    onsets, values, pending = Onsets(), [], None

    def close():
        nonlocal pending
        if len(values) < 4:
            return None
        row = [quantize(v) for v in values[:4]] + [0]
        strength = onsets.push(values[1:4])
        out, pending = pending, row
        if out is not None:
            out[4] = strength
        return out

    for line in lines:
        line = line.strip()
        if line.startswith("frame:"):
            row = close()
            values = []
            if row is not None:
                yield row
        elif "RMS_level=" in line:
            try:
                values.append(float(line.rsplit("=", 1)[1]))
            except ValueError:
                values.append(float("-inf"))
    row = close()
    if row is not None:
        yield row
    if pending is not None:
        yield pending


ANALYSIS = (
    f"aformat=sample_fmts=fltp:sample_rates={RATE}:channel_layouts=mono,asplit=4[a][b][c][d];"
    "[b]lowpass=f=200:p=2[lo];[c]bandpass=f=1100:w=1800:t=h[mi];[d]highpass=f=3500:p=2[hi];"
    f"[a][lo][mi][hi]amerge=inputs=4,asetnsamples=n={FRAME}:p=0,"
    "astats=metadata=1:reset=1:measure_perchannel=RMS_level:measure_overall=none,"
    "ametadata=mode=print:file=-"
)


class Analyzer:
    """Run the track through ffmpeg once, off to the side, and report features in batches."""

    def __init__(self):
        self.proc = None
        self.q = queue.Queue()
        exe = shutil.which("ffmpeg")
        if not exe:
            say(ev="nofeatures", why="ffmpeg is not installed")
            return
        cmd = [exe, "-nostdin", "-hide_banner", "-loglevel", "error", "-threads", "1", "-i", "pipe:0",
               "-vn", "-filter_complex", ANALYSIS, "-f", "null", "-"]
        if shutil.which("nice"):
            cmd = ["nice", "-n", "15"] + cmd
        try:
            self.proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                         stderr=subprocess.DEVNULL, text=False)
        except OSError as e:
            say(ev="nofeatures", why=str(e)[:80])
            return
        self.feeder = threading.Thread(target=self._feed, daemon=True)
        self.reader = threading.Thread(target=self._read, daemon=True)
        self.feeder.start()
        self.reader.start()

    def write(self, data):
        if self.proc:
            self.q.put(data)

    def _feed(self):
        try:
            while True:
                data = self.q.get()
                if data is None:
                    break
                self.proc.stdin.write(data)
        except (BrokenPipeError, OSError):
            pass
        finally:
            try:
                self.proc.stdin.close()
            except OSError:
                pass

    def _read(self):
        text = (raw.decode("ascii", "replace") for raw in self.proc.stdout)
        batch, index = [], 0
        for row in frames_from_stats(text):
            batch.append(row)
            if len(batch) == BATCH:
                say(ev="features", i=index, hop=HOP, frames=batch)
                index += len(batch)
                batch = []
        if batch:
            say(ev="features", i=index, hop=HOP, frames=batch)
            index += len(batch)
        if index == 0:
            say(ev="nofeatures", why="the analysis produced nothing")

    def finish(self, wait=30):
        if not self.proc:
            return
        self.q.put(None)
        self.reader.join(wait)
        self.kill()

    def kill(self):
        if self.proc and self.proc.poll() is None:
            self.proc.kill()


# ---- the pipe ----------------------------------------------------------------------

def open_pipe(path, wait=OPEN_WAIT, alive=lambda: True):
    """Open the named pipe for writing once the player has it open for reading."""
    deadline = time.monotonic() + wait
    while alive():
        try:
            fd = os.open(path, os.O_WRONLY | os.O_NONBLOCK)
        except OSError as e:
            if e.errno != errno.ENXIO:
                raise
            if time.monotonic() > deadline:
                raise FetchError("player", "the player never opened the stream")
            time.sleep(0.01)
            continue
        os.set_blocking(fd, True)
        return fd
    raise FetchError("player", "stopped")


def run(spec, out, analyze, source=None):
    """Fetch `spec` into the pipe at `out`. Returns the process exit code."""
    started = time.monotonic()
    os.makedirs(os.path.dirname(out), mode=0o700, exist_ok=True)
    try:
        os.unlink(out)
    except FileNotFoundError:
        pass
    os.mkfifo(out, 0o600)
    stop = threading.Event()
    analyzer = Analyzer() if analyze else None
    signal.signal(signal.SIGTERM, lambda *_: stop.set())
    chunks, failure, wire = queue.Queue(), [], [0]

    def download():
        try:
            gen = source(spec) if source else (track_zip if spec["kind"] == "zip" else track_url)(spec, counter=wire)
            for piece in gen:
                if stop.is_set():
                    return
                chunks.put(piece)
                if analyzer:
                    analyzer.write(piece)
        except Exception as e:  # reported below, never raised across the thread
            failure.append(classify(e))
        finally:
            chunks.put(None)

    say(ev="ready")
    threading.Thread(target=download, daemon=True).start()
    fd, sent, code = None, 0, 0
    try:
        fd = open_pipe(out, alive=lambda: not stop.is_set())
        while not stop.is_set():
            try:
                piece = chunks.get(timeout=0.2)
            except queue.Empty:
                continue
            if piece is None:
                break
            if sent == 0:
                say(ev="first", ms=int((time.monotonic() - started) * 1000))
            view = memoryview(piece)
            while view:
                n = os.write(fd, view)
                view = view[n:]
            sent += len(piece)
    except BrokenPipeError:
        stop.set()            # the player moved on; nothing is wrong
    except FetchError as e:
        failure.append((e.kind, e.detail))
    finally:
        if fd is not None:
            os.close(fd)
        try:
            os.unlink(out)
        except OSError:
            pass
    if failure:
        kind, detail = failure[0]
        if analyzer:
            analyzer.kill()
        say(ev="error", kind=kind, detail=detail, bytes=sent)
        return EXIT.get(kind, 5)
    if stop.is_set():
        if analyzer:
            analyzer.kill()
        return 0
    if analyzer:
        analyzer.finish()
    say(ev="done", bytes=sent, wire=wire[0], verified=spec.get("verified"),
        ms=int((time.monotonic() - started) * 1000), cost=cost())
    return code


def cost():
    """What this fetch used: CPU seconds and peak memory, its own and the analysis's."""
    me, kids = resource.getrusage(resource.RUSAGE_SELF), resource.getrusage(resource.RUSAGE_CHILDREN)
    return {"cpu": round(me.ru_utime + me.ru_stime, 2), "analysisCpu": round(kids.ru_utime + kids.ru_stime, 2),
            "peakKb": me.ru_maxrss, "analysisPeakKb": kids.ru_maxrss}


def main(argv):
    ap = argparse.ArgumentParser(description="Fetch one track into a named pipe for the player.")
    ap.add_argument("--out", required=True, help="path of the named pipe to create")
    ap.add_argument("--analyze", action="store_true", help="also measure features with ffmpeg")
    ap.add_argument("--spec", required=True, help="the track's location as JSON")
    args = ap.parse_args(argv)
    signal.signal(signal.SIGPIPE, signal.SIG_IGN)
    try:
        spec = json.loads(args.spec)
        if spec.get("kind") not in ("url", "zip") or not str(spec.get("url", "")).startswith("https://"):
            raise ValueError("not a track location")
        spec["start"] = max(0.0, min(0.98, float(spec.get("start", 0.0))))
        runtime = os.environ.get("XDG_RUNTIME_DIR", "")
        out = os.path.abspath(args.out)
        if not runtime or not out.startswith(os.path.abspath(runtime) + os.sep):
            raise ValueError("the pipe must live under XDG_RUNTIME_DIR")
        if os.path.lexists(out) and not stat.S_ISFIFO(os.lstat(out).st_mode):
            raise ValueError("something that is not a pipe is in the way")
    except (ValueError, TypeError) as e:
        say(ev="error", kind="source", detail=f"bad request: {e}"[:120])
        return 5
    return run(spec, out, args.analyze)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
