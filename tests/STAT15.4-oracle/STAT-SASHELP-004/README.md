# STAT-SASHELP-004 — SASHELP example data — El Nino–Southern Oscillation Data / Finland's Lake Laengelmaevesi Fish Catch Data / Exhaust Emissions Data

## Source

S154 / Sashelp Data Sets / `El Nino–Southern Oscillation Data` (PDF pp. 10909–10910); S154 / Sashelp Data Sets / `Finland's Lake Laengelmaevesi Fish Catch Data` (PDF pp. 10910–10911); S154 / Sashelp Data Sets / `Exhaust Emissions Data` (PDF pp. 10911–10912).

## Scope

For El Nino–Southern Oscillation Data; Finland's Lake Laengelmaevesi Fish Catch Data; Exhaust Emissions Data provide reproducible public example data or the compatible loading method explicitly documented in the source; use public or synthetic data only.

## Acceptance criteria

Verify observation counts, variable names/types/labels, class levels, and key summaries against the source; examples must run independently; record data provenance and version rather than substituting randomly similar data for the published data.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [native_contract.sas](native_contract.sas) | captured | 0 | [listing](native_contract.expected.txt) / [log](native_contract.oracle.log) | Published SASHELP data availability, row counts, first observations and descriptors: enso, fish, gas, iris |

**native_contract:** Draft case captures the stated observable contract; it is not exhaustive coverage of the ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
