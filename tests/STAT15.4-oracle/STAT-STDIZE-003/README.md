# STAT-STDIZE-003 — STDIZE — LOCATION / SCALE / Standardization Methods

## Source

S154 / Chapter 115 / `LOCATION Statement` (PDF p. 9462); S154 / Chapter 115 / `SCALE Statement` (PDF p. 9462); S154 / Chapter 115 / `Standardization Methods` (PDF pp. 9464–9466).

## Scope

Implement LOCATION; SCALE; Standardization Methods. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For LOCATION / SCALE / Standardization Methods, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: STDIZE Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: LOCATION, SCALE.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
