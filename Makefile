# Cross-compile the `sas` binary. Zig cross-compiles natively — no external
# toolchain. Output: dist/<triple>/sas[.exe]. Override OPT=Debug for debug builds.
OPT ?= ReleaseFast

# name -> zig target triple
arm     := aarch64-linux-gnu
amd     := x86_64-linux-gnu
windows := x86_64-windows-gnu
macos   := aarch64-macos

.PHONY: all arm amd windows macos wasm clean
all: arm amd windows

arm amd windows macos:
	zig build -Dtarget=$($@) -Doptimize=$(OPT) --prefix dist/$@

# Web demo: builds web/sas.wasm (target/optimize are fixed in build.zig).
wasm:
	zig build wasm

clean:
	rm -rf dist
