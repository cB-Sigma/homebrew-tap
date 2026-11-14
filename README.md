# cB-Sigma Homebrew tap

Homebrew formulae for [uccharan](https://github.com/cB-Sigma/uccharan) and
[bolo](https://github.com/cB-Sigma/bolo).

```sh
brew install cb-sigma/tap/uccharan
brew install cb-sigma/tap/bolo
```

or tap once and use the short names:

```sh
brew tap cb-sigma/tap
brew install uccharan bolo
```

## uccharan

The phonemiser, text normaliser and transliterator, built from the source of the release:

- `uccharan`, the command-line tool: `uccharan -l hi -p piper "नमस्ते दुनिया।"`;
- `libuccharan` (shared and static) and `uccharan.h`, for C and other languages with a C FFI:
  `cc hello.c -I$(brew --prefix)/include -L$(brew --prefix)/lib -luccharan`. An example is in
  `$(brew --prefix uccharan)/share/uccharan/hello.c`.

English and Hindi are built in. The word tables of the other languages are small packs that are
downloaded from the GitHub release the first time a language is used, checked against SHA-256
sums and cached in `~/.cache/uccharan/<version>/`. To fetch them ahead of time:

```sh
uccharan --packs              # the packs and which are installed
uccharan --download de fr ur  # into the cache
```

Building needs Rust, which Homebrew installs as a build dependency; it takes a few minutes.

## bolo

The speech server, installed as `bolo-speech[all]` (sherpa-onnx, faster-whisper, uccharan, PyAV,
Wyoming) from PyPI wheels into a virtualenv of its own, with every dependency pinned.

```sh
brew services start bolo     # start now and at login
brew services stop bolo
bolo serve                   # or run it in the foreground
```

The service serves the web console at <http://127.0.0.1:8000/> and the API at
`http://127.0.0.1:8000/v1/`. It keeps its models in `$(brew --prefix)/var/bolo` and logs to
`$(brew --prefix)/var/log/bolo.log`. Settings go into `~/.config/bolo/config.toml` or `BOLO_*`
environment variables ([configuration](https://github.com/cB-Sigma/bolo/blob/main/docs/configuration.md)).

bolo is CPU-first. The extras outside `all` (eSpeak NG, which is GPL-3.0-or-later; kokoro-onnx;
whispercpp, moonshine, s2s, turn, orpheus, sip, webrtc, text) are opt-in; add them to the
formula's virtualenv with its pip, within the pinned versions:

```sh
$(brew --prefix bolo)/libexec/bin/pip install -c $(brew --prefix bolo)/libexec/constraints.txt \
  "bolo-speech[espeak]==$(bolo --version | cut -d' ' -f2)"
```

Extras added this way are not kept across `brew upgrade bolo`: add them again after an upgrade.
`brew info bolo` shows these notes again.

## Upgrading

```sh
brew update
brew upgrade uccharan bolo
```

New releases of both projects reach this tap on their own: a workflow here checks for them twice
a day, tests the updated formulae on macOS and Linux and publishes them, so a new version appears
within about 12 hours of its release. If a new version fails its tests here, the tap stays at the
previous one until the problem is fixed.

## Platforms

| | uccharan | bolo |
| --- | --- | --- |
| macOS, Apple Silicon | yes | macOS 14 (Sonoma) or later |
| macOS, Intel | yes | macOS 14 or later, with onnxruntime 1.23 (its last release for Intel Macs) |
| Linux x86_64 | yes | yes |
| Linux arm64 | yes | yes |

bolo needs macOS 14 or later because onnxruntime and PyAV publish their Apple Silicon wheels for
macOS 14 and later only. On Linux, bolo's wheels are manylinux builds, which use the system's
glibc and zlib. No bottles are published: uccharan is built from source, and bolo installs
prebuilt wheels.

## Problems

Problems with a formula or with installing through Homebrew:
[issues of this tap](https://github.com/cB-Sigma/homebrew-tap/issues). Problems with the programs
themselves: [uccharan issues](https://github.com/cB-Sigma/uccharan/issues),
[bolo issues](https://github.com/cB-Sigma/bolo/issues). Please include the output of
`brew config` and `brew doctor`.
