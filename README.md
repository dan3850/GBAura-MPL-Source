# GBAura — MPL Source Compliance

This repository provides the Source Code Form and source-level modifications
required for the MPL-2.0-covered portions distributed with GBAura.

It is intentionally separate from GBAura's proprietary application/frontend
source code.

## Covered upstream project

- Project: mGBA
- Upstream: https://github.com/mgba-emu/mgba
- Upstream commit: `c3c8e5e813f245028de118a56734e1dc0f35ce2a`
- License: Mozilla Public License 2.0

The exact upstream snapshot is referenced by this repository and the
GBAura-specific source transformations are provided in
`patches/mgba_mpl_modifications.cmake`.

## GBAura release/source baseline

The compliance package was prepared from GBAura commit:

`03d7a3f1f8fa577256fd6c5b1b1bb0536e732858`

The Android build applies the MPL modification module to an isolated writable
copy of the pinned mGBA source tree before compiling it.

## Additional MPL-covered GBAura source

`gbaura-mpl/SaveConverterUtil.java` is distributed here under MPL-2.0 because
that file carries mGBA-derived provenance and is explicitly licensed under
MPL-2.0.

## Reproducing the modified mGBA Source Code Form

1. Obtain mGBA at the exact commit listed above.
2. Configure `mgba_v028_SOURCE_DIR` to point to a writable copy of that source.
3. Run the CMake script in `patches/mgba_mpl_modifications.cmake`.
4. The script performs the same source transformations used by GBAura's Android
   build.

The repository also records the affected-file inventory and verification data so
the modified Source Code Form can be checked against the release baseline.

## License

The MPL-covered files and GBAura modifications published here are available
under the Mozilla Public License 2.0. See `LICENSE`.

Third-party material inside the upstream mGBA source tree remains under its
respective upstream licenses and notices.

## Scope

This repository is a source-compliance repository. It does **not** grant a
license to unrelated proprietary GBAura code, assets, trademarks, artwork, or
other material not included here.
