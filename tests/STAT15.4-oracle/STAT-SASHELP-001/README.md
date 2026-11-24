# STAT-SASHELP-001 — SASHELP example data — Baseball Data / Tropical Rain Forest Tree Data / 2003 Birth Weight Data Set

## Source

S154 / Sashelp Data Sets / `Baseball Data` (PDF pp. 10897–10899); S154 / Sashelp Data Sets / `Tropical Rain Forest Tree Data` (PDF pp. 10899–10901); S154 / Sashelp Data Sets / `2003 Birth Weight Data Set` (PDF pp. 10901–10902).

## Scope

For Baseball Data; Tropical Rain Forest Tree Data; 2003 Birth Weight Data Set provide reproducible public example data or the compatible loading method explicitly documented in the source; use public or synthetic data only.

## Acceptance criteria

Verify observation counts, variable names/types/labels, class levels, and key summaries against the source; examples must run independently; record data provenance and version rather than substituting randomly similar data for the published data.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [native_contract.sas](native_contract.sas) | captured | 0 | [listing](native_contract.expected.txt) / [log](native_contract.oracle.log) | Published SASHELP data availability, row counts, first observations and descriptors: mileages, quakes, springs, thick, vote1980, baseball, bei, birthwgt, bmimen |

**native_contract:** Draft case captures the stated observable contract; it is not exhaustive coverage of the ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
