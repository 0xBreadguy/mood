# Contributing

Start with [README.md](README.md) and the [product brief](docs/product.md).
Keep decided behavior, open proposals, and implemented defaults distinct. The
main bar surface shows only mood and playback state—no track titles, album
art, or queue clutter.

Keep changes focused and explain what they let someone do. Report actual test
coverage and unresolved gaps honestly (for example, silent Omabox runs do not
substitute for listening to audio or checking physical trackpads and
monitors).

## Surfaces (looks)

To add or change the plugin's visual presentation, work inside a surface under
`plugin/surfaces/` and leave the playback and interaction mechanics alone.
Read [docs/surfaces.md](docs/surfaces.md) first for the full contract.

- Input handling, keyboard focus, accessible names, playback, and settings
  belong to the plugin core, not a surface.
- `plugin/surfaces/plain/` is the neutral reference and fallback, not a
  design.
- Verify custom surfaces against the behavior suite with
  `MOOD_SURFACE=<id> tools/box-check.sh`.

## Music catalog

- Do not edit `catalog/catalog.json` by hand. Regenerate it with
  `tools/build_catalog.py` and validate it with
  `tools/build_catalog.py --check`.
- Any new music source needs its source page, creator, verified license (see
  [docs/music-sources.md](docs/music-sources.md)), and a listening pass. Do
  not equate an open code license with rights to its audio.

## Development and testing

Develop and test GUI changes inside an Omabox hidden desktop
(`omabox up --stock --audio --plugin "$PWD"`) rather than on a live desktop.
Cloning or pulling this repository must have no live-desktop side effects.

Run the checks before calling plugin work done:

```sh
node --test test/
python3 -m unittest discover -s test
tools/build_catalog.py --check
tools/box-check.sh
```

## What stays out of Git

Do not commit credentials, local playback state, caches, downloaded music, or
machine-specific paths.

## License

Plugin code and documentation in this repository are released under the
[MIT License](LICENSE). Linked music tracks are not bundled here and remain
under their upstream CC0 dedications.
