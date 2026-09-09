# sas7bdat_read — native sas7bdat (`.sas7bdat`) LIBNAME engine

Reads a native SAS dataset (`.sas7bdat`) through a LIBNAME pointed **straight at
the file** (`libname s "inputs/te.sas7bdat"`), copies it out with a DATA step,
and reproduces the golden dataset exactly (2 rows, 6 character columns).

The file-libname form is the case QA caught: before the fix a libref pointed at a
real `.sas7bdat` resolved members as `dir/member.sas7bdat` (i.e. inside the file),
missed, and silently loaded nothing — indistinguishable from a bogus path. Now
the loader detects the `.sas7bdat`/`.xpt` extension and reads the file itself.

## Source

`inputs/te.sas7bdat` — an invented SDTM TE (Trial Elements) table for the
fictional study `STUDY-01`. TE is a trial-design domain, so there is no subject
data in it by construction. Written by opensas itself (`PROC COPY` into a
directory libname), so this fixture proves the **wiring**, not the reader's
byte-level conformance:

- byte-exactness of the reader against **real SAS-authored** files is asserted
  separately in `src/sas7bdat.zig`, against a pyreadstat oracle, using the
  public haven test files (`hadley`, `test7`, `tagged_na` in `src/testdata/`);
- this tier proves file-libname resolution and the end-to-end dataset copy.

To regenerate the input:

```sas
data te;
  length STUDYID $15 DOMAIN $2 ETCD $8 ELEMENT $40 TESTRL $40 TEENRL $40;
  STUDYID="STUDY-01"; DOMAIN="TE";
  ETCD="SCRN"; ELEMENT="Screening";
  TESTRL="Informed consent date"; TEENRL="First follow-up visit - 1 day"; output;
  ETCD="FULT"; ELEMENT="Long-term Follow-up";
  TESTRL="First follow-up visit"; TEENRL="End of the study"; output;
run;
libname w "tests/programs/sas7bdat_read/inputs";
proc copy in=work out=w; select te; run;
```

Then delete the `te.csv` that `PROC COPY` also stamps — a CSV sibling would let
the directory-libname tests (`existdisk`, `opendisk`, `vtable_disk`) pass on the
CSV path and mask a regression in the sas7bdat probe.

## What it exercises (end-to-end)
- `sas7bdat.zig` — the reader (32-bit LE uncompressed; header/page/subheader
  metadata, per-column offset/width/type, char decode).
- `io.readByExt` / `io.readSas7bdat` — the io-layer engine dispatch by extension.
- `main.loadLibInputs` — file-libname resolution: a libref whose path ends in
  `.sas7bdat`/`.xpt` is read as that single member — the wiring proved here.
- `set` / DATA step / `writeCsv` round-trip.

This same file backs the `existdisk`, `existdisk_lazyload`, `fn_pathname`,
`opendisk` and `vtable_disk` corpus fixtures (disk-only member resolution) and
the `GAP-opendisk` unit test in `src/dsfns.zig` — it is 2 obs / 6 vars with
`DOMAIN` as variable 2, which is what those tests assert.

PROC PRINT reads the same LIBNAME member (`tests/corpus/sas7bdat_charslice.sas`);
the XPORT twin of this path is covered by `xport_read`.
