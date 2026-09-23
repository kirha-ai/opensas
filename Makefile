# Cross-compile the `sas` binary. Zig cross-compiles natively — no external
# toolchain. Output: dist/<triple>/sas[.exe]. Override OPT=Debug for debug builds.
OPT ?= ReleaseFast

# GH#10 ISS-versionflag: the release workflow passes the git tag through
# (`VERSION=v0.6.5 make arm`), so the binary self-reports its release even from
# a shallow CI checkout. Unset locally → no flag → build.zig falls back to
# `git describe --tags --always`, then "dev". The guard matters: an EMPTY
# -Dversion= would reach b.option as "" and override the fallback with "".
ifeq ($(strip $(VERSION)),)
VERSION_FLAG :=
else
VERSION_FLAG := -Dversion=$(VERSION)
endif

# name -> zig target triple
arm     := aarch64-linux-gnu
amd     := x86_64-linux-gnu
windows := x86_64-windows-gnu
macos   := aarch64-macos

.PHONY: all arm amd windows macos wasm clean
all: arm amd windows

arm amd windows macos:
	zig build $(VERSION_FLAG) -Dtarget=$($@) -Doptimize=$(OPT) --prefix dist/$@

# Web demo: builds web/sas.wasm (target/optimize are fixed in build.zig).
wasm:
	zig build $(VERSION_FLAG) wasm

clean:
	rm -rf dist
