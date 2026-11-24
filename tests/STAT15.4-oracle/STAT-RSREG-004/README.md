# STAT-RSREG-004 — RSREG — RIDGE / Introduction to Response Surface Experiments / Coding the Factor Variables

## Source

S154 / Chapter 108 / `RIDGE Statement` (PDF pp. 8877–8878); S154 / Chapter 108 / `Introduction to Response Surface Experiments` (PDF pp. 8879–8881); S154 / Chapter 108 / `Coding the Factor Variables` (PDF p. 8881).

## Scope

Implement RIDGE; Introduction to Response Surface Experiments; Coding the Factor Variables. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For RIDGE / Introduction to Response Surface Experiments / Coding the Factor Variables, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 108.1: A Saddle Surface Response Using Ridge Analysis; explicit statements: RIDGE |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: RIDGE. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
