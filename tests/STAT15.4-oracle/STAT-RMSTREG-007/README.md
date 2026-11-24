# STAT-RMSTREG-007 — RMSTREG — ESTIMATE / TEST / Type 3 Tests and Joint Tests

## Source

S154 / Chapter 106 / `ESTIMATE Statement` (PDF pp. 8741–8742); S154 / Chapter 106 / `TEST Statement` (PDF p. 8748); S154 / Chapter 106 / `Type 3 Tests and Joint Tests` (PDF pp. 8751–8752).

## Scope

Implement ESTIMATE; TEST; Type 3 Tests and Joint Tests. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For ESTIMATE / TEST / Type 3 Tests and Joint Tests, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: ESTIMATE, TEST.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
