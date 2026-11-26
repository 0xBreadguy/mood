# Music source investigation

These are candidates for a curated catalog. No music is bundled. Access checks
below were made on 2026-11-20/21; URLs and catalogs can change.

The initial catalog uses two collections: Open Lo-Fi, and three Alec Penn
Radio genres (Lo-Fi, Neo-Classical and Psychedelic Jazz). The plugin's
catalog, `catalog/catalog.json`, was generated from them on 2026-11-21 and
points at 451 tracks. [What the plugin does with them](#in-the-plugin) is at
the end. Everything else here is still a candidate, and a full listening pass
has not been completed yet.

## Open Lo-Fi

[Repository](https://github.com/btahir/open-lofi) ·
[Catalog](https://github.com/btahir/open-lofi/blob/main/catalog.json)

The creator offers Suno-generated music under CC0, organized into categories
including focus, weather, ambient and late-night music. A JSON catalog lists
the tracks and filenames. It is a promising thematic fit.

The audio is distributed as a release ZIP, rather than individual audio
files in the repository. Using it requires a collection download/cache or
individual-file hosting. Reading its catalog alone does not establish a
streamable source.

Checked again on 2026-11-21, from the repository's metadata only:

- 166 MP3 tracks in 10 categories: activities (29, labelled "Focus, Rituals
  & Daily Routines"), seasonal-weather (27), ambient-lofi (21), soul-rnb
  (21), late-night (18), funk-soul (14), jazzhop (12), chillhop (8),
  asian-lofi (8) and hybrid (8).
- One release, v1.0.0 from 2026-03-14, with one asset: `openlofi.zip`,
  554.5 MB. The repository has had no pushes since 2026-03-15.
- The Git tree holds the catalog, README, license, an image and a release
  script. There are no per-track files or URLs anywhere.
- Each catalog entry has a title, a filename and a category. There are no
  durations, IDs or per-track license fields; the license is stated once
  for the collection.
- The README says every track was generated with Suno v5 by the creator, who
  states ownership as a paying member and dedicates them to the public
  domain with no attribution required. That statement is the creator's and
  hasn't been checked further.

There are no per-track links, but the ZIP can be read piecemeal, so a track
can still be fetched by itself:

- The release server answers explicit byte-range requests (`206`). It
  refuses the "last N bytes" form with `501`, so both ends must be given.
- The ZIP's index is 15.5 KB at the end of the file. It lists all 166 tracks
  with their positions and checksums, and its names match the catalog
  exactly.
- Tracks are compressed inside the ZIP, so a range isn't playable as it
  arrives; it has to be unpacked first. Tracks are 1.7 to 6.8 MB, median
  3.2 MB.
- [`tools/audition.py`](../tools/audition.py) does this. Its check fetched
  three whole tracks (9.7 MB in all) by range, unpacked them in memory,
  matched their checksums and read lengths of 2:16, 2:22 and 3:12. Nothing
  was kept and nothing was played.

This depends on GitHub continuing to serve ranges for that release and on
the creator keeping it up; it is not a promised music host. Each play
transfers the track again unless recent tracks are cached, so it is light on
disk and install rather than on data over time. Nobody has listened yet.

Compared with a plain stream, measured on 2026-11-21 with `mpv` and its
sound output off, one run each on one connection:

- A plain stream, meaning a direct link to a 6.4 MB DURU MP3, started in
  0.6 s. The player had read the whole file ahead within six seconds and
  held it in memory. Nothing was written to disk.
- The median Open Lo-Fi track (3.2 MB, 2:33, about 168 kbps), fetched whole
  from the ZIP, arrived in 0.6 s and started 0.8 s after the request.
  Unpacked as it arrived and piped into the player, it started in 0.4 s and
  its checksum still matched. Nothing was written to disk either way.
- The ZIP's compression saves 0.4%, so a slice is as many bytes as the same
  MP3 by direct link: about 75 MB per hour of listening at that bitrate.
- The player process held 68 to 88 MB in all three runs. 26 to 43 MB of
  that was its own and the rest was shared libraries. The track accounted
  for 3 to 10 MB.
- Fetching the ZIP's index took 0.6 s.

A third party mirrors the collection as single files.
[thaxas-lofi](https://github.com/MdShahnawazSheikh/thaxas-lofi) holds all
166 tracks re-encoded to 96 kbps (1.0 to 3.6 MB, median 1.8 MB) with the
catalog unchanged. A range request through jsDelivr, pinned to a commit,
returned `206`. That would make Open Lo-Fi a plain stream at a little over
half the data. The cost is lower sound quality and a dependence on someone
else's mirror and on jsDelivr continuing to serve it.

## Alec Penn Radio

[Lo-Fi item](https://archive.org/details/alecpennradio-lofi) ·
[All items](https://archive.org/search?query=creator%3A%22Alec+Penn+Radio%22)

One creator's catalog on the Internet Archive, added in October and
November 2026: 1,402 MP3 tracks (6.2 GB) in 21 items, one item per genre.
Every item is marked CC0 and described as "AI co-created" and "music made
to be given away". The uploading account carries the creator's name.

The genres that might suit coding are Lo-Fi (107 tracks, median 2:15),
Neo-Classical (98, 3:16), Psychedelic Jazz (80, 3:56), Chillstep (39,
3:22), Meditation Zen (21, 4:45), Acoustic Folk (27, 3:57) and Synthwave
(11, 3:45). The rest include House (146), Workout (259), YouTube Shorts
(201), Slow Jams (87) and experimental pop, rap and dance.

Each track has its own link, and a range request returned `206` after one
redirect. The Archive's metadata lists every file with its size and length,
so a pointer list can be generated from it.

Not known: which tool made the tracks, whether they have vocals and how
they sound. The creator's own site is an app with no readable license text,
so the CC0 statement rests on the Archive items alone.

## CC0-1.0 Music

[Repository](https://github.com/SoundSafari/CC0-1.0-Music)

A researcher's collection of music that was marked CC0 or public domain on
the sites it came from: 9,224 audio files, 84 GB, last changed in December
2023. It is human-made, not AI. 5,181 tracks from 668 artists came from the
Free Music Archive, including HoliznaCC0 (444, whose releases include
lo-fi, jazz and 20-minute meditations), Monplaisir (474), Komiku (273) and
Loyalty Freak Music (93). The rest came from Freesound (2,932, largely
sounds and loops), Chosic (798) and FreePD (302).

Files are ordinary files in the repository. A raw link to a HoliznaCC0
track returned `206` with an `audio/mpeg` type and real audio bytes.

There are no categories. A filename gives only artist and title, so moods
would have to be assigned by us, probably artist by artist. Tracks are
larger, with a median of 6.3 MB for the Free Music Archive ones. The CC0
status is the collector's record of each source page, so check the
artist's own page before relying on a track. The raw-link caution under
DURU applies here too.

## Other Internet Archive collections

Smaller AI-made collections, each marked CC0 by its uploader:

- [AI Baroque music](https://archive.org/details/ai-baroque-music) (80
  tracks, median 2:51) and
  [AI Classical](https://archive.org/details/ai-classical) (57, 3:25), from
  an unnamed uploader.
- [A suno music archive](https://archive.org/details/a-suno-music-archive):
  106 tracks the uploader made with Suno, several of them takes of the same
  song.
- [Elf Girl](https://archive.org/details/Elf-Girl-001-Through-009-MP3s-320kbps):
  213 tracks made with Udio v1.5 across many genres, 4.3 GB at 320 kbps.
- [AI generated Music](https://archive.org/details/Aigenerated): 197 tracks
  made with producer.ai, as WAV files (10.5 GB). That is too heavy to fetch
  per play.

## Checked and set aside

- Hugging Face collections of Suno and Udio output, for example a 626 GB
  Udio set tagged CC0. They were gathered from other people's accounts and
  the collector chose the license; one such set has a discussion titled
  "License is wrong and illegal". They are also packed into multi-gigabyte
  shards.
- A lo-fi set on Hugging Face: 817 GB under a non-commercial license.
- Openverse's CC0 results for these styles: Freesound loops, mostly under a
  minute.
- Internet Archive items tagged CC0 that are plainly copies of commercial
  releases or of video-site uploads.
- Skank Bank's library of 2,449 Suno-made drum and bass tracks, described
  in an article as free to use. Its terms weren't read and the style is a
  stretch.

## DURU CC0 BGM

[Repository and creator's license statement](https://github.com/uncle-sheepsky/duru-ai-cc0-bgm)

Individual MP3s are present in the repo. A sample raw MP3 URL returned
`206 Partial Content` with an `audio/mpeg` content type for a byte-range
request. That establishes basic HTTP access, not full native playback or
long-term hosting reliability.

The creator describes the music as composed in Python, with synthesized
instruments and, for some pieces, CC0 samples. It isn't a neural music-model
output collection. The library includes short loops and video backgrounds
with deliberate silent sections, which need to be excluded or handled
explicitly when curating coding music.

## ccMixter

[Query API documentation](https://ccmixter.org/query-api)

The API returns searchable metadata, tags, license URLs and individual audio
download URLs. A query for ambient, instrumental uploads under the `by`
license filter returned metadata successfully. A sample MP3 returned
`200 OK` and an MP3 header with a normal request. A different sample's
byte-range request returned `403`, so request behavior needs investigation.

Select complete pieces carefully: API results may include mixes, alternate
versions, short edits or samples. Preserve per-track attribution. Do not
assume a tag or the site's existence establishes either musical fit or a
uniform license across the catalog.

## CC0 Media Library

[Repository](https://github.com/jfpx/cc0-media-library) ·
[Resource index](https://raw.githubusercontent.com/jfpx/cc0-media-library/main/index.json)

A versioned collection with mood/style tags, stable IDs, creator notices,
durations and hashes. The index and catalog were accessible. Audio is
distributed as a ZIP; individual Ogg files were not found in the inspected
Git tree. This is another collection-download or hosting candidate rather
than a verified individual-track streaming endpoint. Some pieces are short
game-oriented loops, so auditioning matters.

## What a source must pass

- Listen for sustained coding suitability, distracting speech or effects,
  abrupt endings, long silence and excessive repetition.
- Verify audio access in the eventual backend, including startup, pause,
  repeat access, failures and any needed range/seek behavior.
- Keep the creator's source page and track-specific license/credits. A code
  license does not establish a music license.
- On the Internet Archive and Hugging Face the license tag is whatever the
  uploader picked. Rely on it only where the uploader is the creator.
- Distinguish provider permission and hosting suitability from a single
  successful download. Do not treat GitHub raw URLs as a promised music CDN.
- Keep a small curated manifest in this repo; source adapters and future
  collection contributions can expand it without changing the primary UI.

No listening-quality judgment or reliability test has been completed. FreePD
was also investigated, but its official site reported closure, so it is not a
current source candidate.

## In the plugin

Checked on 2026-11-21, in Omabox, with the sound going nowhere.

`tools/build_catalog.py` builds `catalog/catalog.json` from metadata alone:

- **Open Lo-Fi:** its `catalog.json` at repository commit `49a4aa72`, the
  index of the v1.0.0 release ZIP (554,502,698 bytes, the release's own
  SHA-256 recorded), and each track's 30-byte header inside the ZIP, read by
  range, to learn where its data starts. 166 tracks, each a byte range. That
  took about 100 KB of requests; the whole catalog run took 34 s.
- **Alec Penn Radio:** the Internet Archive's metadata for the three items,
  with each item's last-updated time recorded. 285 tracks, each a direct link
  with the Archive's own size, length and CRC-32. An item whose license isn't
  CC0 is refused. The uploader's address in the metadata is not copied.

Each track carries its source page and license. The license is the
collection's own statement in both cases: Open Lo-Fi states it once for the
whole collection, and the Archive items carry the uploader's choice, where the
uploading account bears the creator's name. Neither has been checked further.

The plugin's fetcher plays from those pointers:

- A ZIP track is one ranged request. The archive's total size and the entry's
  own header are checked on the first bytes, the data is unpacked as it
  arrives, and the checksum is compared at the end. First bytes arrived in 0.2
  to 0.4 s and playback started 0.5 s after asking.
- A direct link is one request, with one redirect. Its length is compared with
  the catalog before anything plays, and its checksum at the end. First bytes
  arrived in 0.7 to 0.8 s and playback started in about 1.1 s.
- Across a few dozen plays in one sitting, every checksum that was looked at
  matched and no request was refused. That is one evening on one connection, not a
  reliability test, and says nothing about either host's view of this use.

If the Open Lo-Fi release is ever replaced, its tracks fail with "the
collection has changed" until the catalog is regenerated; nothing is played
from a ZIP that doesn't match. The third-party single-file mirror above is not
used. It would enter the catalog as direct links, with no change to the plugin.
