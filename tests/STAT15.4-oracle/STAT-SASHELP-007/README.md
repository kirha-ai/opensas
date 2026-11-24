# STAT-SASHELP-007 — SASHELP example data — Hot-Spring Locations in the United States / Coal Seam Thickness Data / 1980 US Presidential Election Data

## Source

S154 / Sashelp Data Sets / `Hot-Spring Locations in the United States` (PDF pp. 10922–10923); S154 / Sashelp Data Sets / `Coal Seam Thickness Data` (PDF pp. 10923–10924); S154 / Sashelp Data Sets / `1980 US Presidential Election Data` (PDF p. 10924).

## Scope

For Hot-Spring Locations in the United States; Coal Seam Thickness Data; 1980 US Presidential Election Data provide reproducible public example data or the compatible loading method explicitly documented in the source; use public or synthetic data only.

## Acceptance criteria

Verify observation counts, variable names/types/labels, class levels, and key summaries against the source; examples must run independently; record data provenance and version rather than substituting randomly similar data for the published data.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [native_contract.sas](native_contract.sas) | captured | 0 | [listing](native_contract.expected.txt) / [log](native_contract.oracle.log) | Published SASHELP data availability, row counts, first observations and descriptors: springs, thick, vote1980 |

**native_contract:** Draft case captures the stated observable contract; it is not exhaustive coverage of the ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
