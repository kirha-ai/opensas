# STAT-CALIS-022 — CALIS — EFFPART / Total, Direct, and Indirect Effects

## Source

S154 / Chapter 33 / `EFFPART Statement` (PDF pp. 1550–1551); S154 / Chapter 33 / `Total, Direct, and Indirect Effects` (PDF pp. 1796–1799).

## Scope

Implement EFFPART; Total, Direct, and Indirect Effects. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For EFFPART / Total, Direct, and Indirect Effects, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: CALIS Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: EFFPART.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
