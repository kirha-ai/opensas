# STAT-SASHELP-002 — SASHELP example data — Body Mass Index for Men / Isopod Burrows Data / Bone Marrow Transplant Data

## Source

S154 / Sashelp Data Sets / `Body Mass Index for Men` (PDF pp. 10902–10903); S154 / Sashelp Data Sets / `Isopod Burrows Data` (PDF pp. 10903–10905); S154 / Sashelp Data Sets / `Bone Marrow Transplant Data` (PDF pp. 10905–10906).

## Scope

For Body Mass Index for Men; Isopod Burrows Data; Bone Marrow Transplant Data provide reproducible public example data or the compatible loading method explicitly documented in the source; use public or synthetic data only.

## Acceptance criteria

Verify observation counts, variable names/types/labels, class levels, and key summaries against the source; examples must run independently; record data provenance and version rather than substituting randomly similar data for the published data.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [native_contract.sas](native_contract.sas) | captured | 0 | [listing](native_contract.expected.txt) / [log](native_contract.oracle.log) | Published SASHELP data availability, row counts, first observations and descriptors: bmimen, burrows, bmt, bweight |

**native_contract:** Draft case captures the stated observable contract; it is not exhaustive coverage of the ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
