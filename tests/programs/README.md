# tests/programs — real-world program fixtures

Second corpus tier. Where `tests/corpus/*.sas` diffs **stdout**, these fixtures
run a real **dataset-in → dataset-out** program and diff the **output dataset**.

## Layout

```
tests/programs/<name>/
  program.sas        the program (librefs point at inputs/ and output/)
  inputs/*.csv       input datasets, one CSV per dataset (filename = dataset name)
  expected/*.csv     golden output datasets
  output/            produced at runtime (gitignored); compared to expected/
```

## CSV convention

- Row 1 = column names. Column order is significant (SAS variable order).
- Character missing = empty field. Numeric missing = `.` (SAS convention).
- Fields with leading/trailing spaces are quoted (e.g. `" A "`) — the raw data
  deliberately keeps padding so `strip()` is exercised.

## Runner

`zig build programs` runs every fixture: it maps `libname source "inputs"` /
`libname target "output"` to those dirs, runs `program.sas`, then structurally
diffs every `output/*.csv` against `expected/*.csv` (columns, order, values).

## dm/ — CDISC SDTM Demographics

Maps a raw `SUBJECTS` enrolment listing to the SDTM `DM` domain. Exercises
LIBNAME, LENGTH, LABEL, `input()`/`put()` with `yymmdd10.`, `catx`, `yrdif`,
`strip`, `upcase`, `select`/`when`, if/then/do. 4 invented subjects cover:
normal, missing birth date (`AGE=.`), missing last dose (empty `RFENDTC`),
mixed-case and padded inputs.
