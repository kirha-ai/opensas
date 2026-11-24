# STAT-SASHELP-005 — SASHELP example data — Fisher (1936) Iris Data / Junk Email Data / Leukemia Data Sets

## Source

S154 / Sashelp Data Sets / `Fisher (1936) Iris Data` (PDF pp. 10912–10914); S154 / Sashelp Data Sets / `Junk Email Data` (PDF pp. 10914–10916); S154 / Sashelp Data Sets / `Leukemia Data Sets` (PDF pp. 10916–10918).

## Scope

For Fisher (1936) Iris Data; Junk Email Data; Leukemia Data Sets provide reproducible public example data or the compatible loading method explicitly documented in the source; use public or synthetic data only.

## Acceptance criteria

Verify observation counts, variable names/types/labels, class levels, and key summaries against the source; examples must run independently; record data provenance and version rather than substituting randomly similar data for the published data.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [native_contract.sas](native_contract.sas) | captured | 0 | [listing](native_contract.expected.txt) / [log](native_contract.oracle.log) | Published SASHELP data availability, row counts, first observations and descriptors: iris, junkmail, leutrain, leutest, margarin |

**native_contract:** Draft case captures the stated observable contract; it is not exhaustive coverage of the ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
