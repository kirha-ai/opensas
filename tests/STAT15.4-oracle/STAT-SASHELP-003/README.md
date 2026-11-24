# STAT-SASHELP-003 — SASHELP example data — 1997 Birth Weight Data / Class Data / Comet Data

## Source

S154 / Sashelp Data Sets / `1997 Birth Weight Data` (PDF pp. 10906–10907); S154 / Sashelp Data Sets / `Class Data` (PDF pp. 10907–10908); S154 / Sashelp Data Sets / `Comet Data` (PDF pp. 10908–10909).

## Scope

For 1997 Birth Weight Data; Class Data; Comet Data provide reproducible public example data or the compatible loading method explicitly documented in the source; use public or synthetic data only.

## Acceptance criteria

Verify observation counts, variable names/types/labels, class levels, and key summaries against the source; examples must run independently; record data provenance and version rather than substituting randomly similar data for the published data.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [native_contract.sas](native_contract.sas) | captured | 0 | [listing](native_contract.expected.txt) / [log](native_contract.oracle.log) | Published SASHELP data availability, row counts, first observations and descriptors: bweight, class, comet, enso |

**native_contract:** Draft case captures the stated observable contract; it is not exhaustive coverage of the ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
