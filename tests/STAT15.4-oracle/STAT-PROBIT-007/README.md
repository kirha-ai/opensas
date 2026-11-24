# STAT-PROBIT-007 — PROBIT — ESTIMATE / TEST / Inverse Confidence Limits

## Source

S154 / Chapter 100 / `ESTIMATE Statement` (PDF pp. 8109–8110); S154 / Chapter 100 / `TEST Statement` (PDF p. 8120); S154 / Chapter 100 / `Inverse Confidence Limits` (PDF pp. 8127–8128).

## Scope

Implement ESTIMATE; TEST; Inverse Confidence Limits. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For ESTIMATE / TEST / Inverse Confidence Limits, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 100.4: An Epidemiology Study; explicit statements: TEST |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: TEST. Remaining statement variants: ESTIMATE. Removed an unrelated PLM fragment that required an absent item store. The epidemic model now explicitly requests ESTIMATE and TEST for dose, plus inverse limits.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
