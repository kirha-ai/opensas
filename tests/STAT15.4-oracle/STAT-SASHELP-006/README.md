# STAT-SASHELP-006 — SASHELP example data — Margarine Data / Flying Mileages between 10 US Cities Data / Earthquake Locations in the United States

## Source

S154 / Sashelp Data Sets / `Margarine Data` (PDF pp. 10918–10919); S154 / Sashelp Data Sets / `Flying Mileages between 10 US Cities Data` (PDF pp. 10919–10921); S154 / Sashelp Data Sets / `Earthquake Locations in the United States` (PDF pp. 10921–10922).

## Scope

For Margarine Data; Flying Mileages between 10 US Cities Data; Earthquake Locations in the United States provide reproducible public example data or the compatible loading method explicitly documented in the source; use public or synthetic data only.

## Acceptance criteria

Verify observation counts, variable names/types/labels, class levels, and key summaries against the source; examples must run independently; record data provenance and version rather than substituting randomly similar data for the published data.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [native_contract.sas](native_contract.sas) | captured | 0 | [listing](native_contract.expected.txt) / [log](native_contract.oracle.log) | Published SASHELP data availability, row counts, first observations and descriptors: margarin, mileages, quakes, springs |

**native_contract:** Draft case captures the stated observable contract; it is not exhaustive coverage of the ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
