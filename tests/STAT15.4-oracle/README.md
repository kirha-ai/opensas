# SAS/STAT 15.4 ticket oracle cases

Reference: SAS/STAT 15.4 User’s Guide. Runtime verified as SAS 9.04.01M9P06052025, SAS/STAT 15.4.

Current progress: 1422/1422 tickets have authored cases; 1422 tickets have all authored cases captured. Case statuses: {'captured': 1542}. Native SAS results: 1352 clean, 188 with preserved warnings, and 2 intentional negative cases. These are reference captures, not OpenSAS implementation test results.

Each directory is named after its ticket in [stat-jira.md](../../stat-jira.md). Its README records source PDF pages, scope, and the precise behavior each program discriminates.

## Artifacts

- `case.sas`: a standalone program, normally with input in DATALINES or a documented SASHELP data set. [inputs.md](inputs.md) indexes the public data dependencies. Each case resets WORK, ODS, variable naming, and locale. Batch capture shares a SAS session; each source can also run on its own.
- `case.expected.txt`: the actual text listing returned by real SAS. An empty listing is allowed only where the case explicitly expects no listing.
- `case.oracle.log`: the actual SAS log, including ODS TRACE paths and diagnostics where requested.
- `case.expected.rc`: sasrun status: 0 clean, 1 warning, 2 SAS error. These are SAS runner statuses, not OpenSAS exit-code meanings.
- `case.expected.diagnostics.txt`: ERROR/WARNING lines, when present.
- `oracle-manifest.json`: source references, case intent, capture status, source hashes, versions, and provenance. A capture does not imply exhaustive ticket coverage.

Expected results are never manufactured from the manual or OpenSAS. Unexpected program errors and connection failures go under `_attempts/` for repair and are not accepted as expected outputs. Negative cases explicitly declare their allowed SAS error status.

## Capture or resume

```sh
python3 tests/STAT15.4-oracle/tools/capture.py --ticket 'STAT-TTEST-*'
python3 tests/STAT15.4-oracle/tools/capture.py
python3 tests/STAT15.4-oracle/tools/status.py
```

The capture tool calls `/Users/argos/saspy/bin/sasrun CASE.sas -f text --json` in a shared session, preserving each returned listing and log separately. This is equivalent to capturing stdout from the user-supplied `-f text -o -` invocation; no mock mode is used. Fixed-width listings retain their original whitespace. Source hashes make capture resumable after program edits.

## Archive verification

[SHA256SUMS](SHA256SUMS) seals the captured SAS sources, listings, logs, return codes, and diagnostic files. [replay-audit.json](replay-audit.json) records eight sampled cases replayed in three fresh SAS sessions, including standalone Bayesian and traditional graphics programs. All sampled listings, SAS statuses, and diagnostics matched exactly. The audit is a sample, not an independent-session replay of every case.

## Scope and coverage

These are draft fixtures, not a declaration that every acceptance criterion is tested. Some tickets currently have a baseline procedure example; statement variants and edge cases remain to be expanded. [coverage.md](coverage.md) lists these limitations explicitly. Numerical examples can include real SAS warnings about convergence or nonidentifiability; read their logs before treating estimates as a valid fitted model.

Sources use one-based physical PDF pages, matching the backlog. Program comments identify the ticket sources; the manifest additionally records the example pages used for each adaptation. Inputs are inline public/manual data, seeded synthetic data, or installed public SASHELP data. The large PDF itself and extracted chapter text are not copied into this archive.

Validate the archive without connecting to SAS:

```sh
python3 tests/STAT15.4-oracle/tools/validate.py
```

Listings and logs are preserved as returned. Dates, WORK paths, log line/page counters, timing tables, and platform-dependent floating-point details can vary on replay. Compare the relevant tables and diagnostics with justified numerical tolerances; raw log byte equality is not an acceptance rule.

## Remaining verification

Text references cover numerical listings, data set dumps, and diagnostics. Graphics tickets also need image artifacts for full visual verification; a text listing or ODS TRACE alone is not a visual oracle. Design-only and external UI tickets require explicit observable case scope rather than artificial expected files.
