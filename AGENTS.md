# Working on mood

- Read `README.md` and `docs/product.md` first. Keep decisions, proposals and
  implemented behavior distinct. Preserve the mood/playback-only main surface.
- The project is named `mood`, lowercase. Write "the plugin" wherever "mood"
  could be read as a selected mood.
- The plugin is `manifest.json` plus `plugin/` and `catalog/`. A look is a
  surface under `plugin/surfaces/`; read `docs/surfaces.md` before adding or
  changing one, and don't put input handling, playback or settings in a
  surface. `plugin/surfaces/plain` is the reference and fallback, not a design.
- Run `node --test test/`, `python3 -m unittest discover -s test`,
  `tools/build_catalog.py --check` and `tools/box-check.sh` (Omabox, silent)
  before calling plugin work done. Regenerate `catalog/catalog.json` with
  `tools/build_catalog.py`; don't edit it by hand.
- Use `docs/product.md` and general UI principles for interface design. Do not
  use existing music players as design references. Backend documentation is
  appropriate technical input.
- Follow Omarchy plugin conventions for native plugin and system work. Never
  modify packaged Omarchy files or install, enable or restart on a live
  desktop unless the task calls for it.
- Use Omabox before launching, driving or capturing any GUI for development
  or checks. Keep verification evidence tied to the actual revision and report
  unobserved modalities honestly.
- Validate track-specific provenance and licenses. Do not equate an open code
  license with rights to its audio. Keep music out of Git unless deliberately
  authorized and appropriately licensed.
- Inspect status before edits. Make scoped local checkpoint commits after
  meaningful verification. Pushes, publication and live installation require
  authorization. No effects on a machine merely from pulling the repo.
- Update `README.md` when behavior, requirements, install/removal or meaningful
  verification changes. Don't claim hardware compatibility without checking
  that machine. Keep credentials, local paths and personal state out of Git.
