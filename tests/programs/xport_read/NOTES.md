# xport_read — XPORT v5 (`.xpt`) LIBNAME engine

Reads a real SAS Transport (XPORT v5) file as a dataset via a LIBNAME pointed at
a directory of `.xpt` files, and copies it out. Reproduces the golden dataset
exactly (5 rows, 6 cols).

## Source
`inputs/te.xpt` — an SDTM TE (Trial Elements) domain for the fictional `CDISC01`
sample study (all-character), authored by real SAS (its header records
`SAS 9.1 XP_PRO`). No real subject data: TE is a trial-design domain, and the
study, its arms and its "Miracle Drug" treatments are invented sample values.
`expected/te.csv` is that file converted with pyreadstat.

## What it exercises
- `xport.zig` — an XPORT v5 reader for the openly-documented TS-140 format:
  80-byte LIBRARY/MEMBER/DSCRPTR/NAMESTR/OBS header records framing byte-packed
  NAMESTR descriptors (type/length/name) and observation data; char values are
  blank-padded ASCII, numeric values are 8-byte IBM System/360 hex floats.
- `io.readXport` — the io-layer hook the loader calls.
- `main.loadLibInputs` — resolves `src.te` to `inputs/te.csv` first, then falls
  back to `inputs/te.xpt` through the XPORT engine.

The IBM-float path (not exercised by this all-char member) is covered by
`xport.zig`'s unit test and was validated end-to-end against the numeric `ta.xpt`
(TAETORD) domain, byte-exact vs pyreadstat.

ponytail: v5 single-member layout only (the SDTM `.xpt` files here are one member
each); no v8/v9 long-name extension, and the reader is read-only.

Expected CSV keeps the pyreadstat LF endings; the runner's structural diff
handles either.
