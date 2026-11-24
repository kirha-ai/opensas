# STAT-PSMATCH-004 — PSMATCH — MATCH / PSDATA / PSWEIGHT

## Source

S154 / Chapter 101 / `MATCH Statement` (PDF pp. 8223–8230); S154 / Chapter 101 / `PSDATA Statement` (PDF p. 8232); S154 / Chapter 101 / `PSWEIGHT Statement` (PDF pp. 8233–8234).

## Scope

Implement MATCH; PSDATA; PSWEIGHT. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For MATCH / PSDATA / PSWEIGHT, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context; explicit statements: MATCH |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: MATCH. Remaining statement variants: PSDATA, PSWEIGHT.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
