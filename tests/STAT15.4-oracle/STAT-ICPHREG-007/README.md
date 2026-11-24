# STAT-ICPHREG-007 — ICPHREG — HAZARDRATIO / TEST

## Source

S154 / Chapter 70 / `HAZARDRATIO Statement` (PDF pp. 5221–5223); S154 / Chapter 70 / `TEST Statement` (PDF p. 5229).

## Scope

Implement HAZARDRATIO; TEST. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For HAZARDRATIO / TEST, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: ICPHREG Procedure; explicit statements: HAZARDRATIO |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: HAZARDRATIO. Remaining statement variants: TEST.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
