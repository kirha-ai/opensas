# STAT-ICPHREG-005 — ICPHREG — BASELINE / Model and Likelihood / Computational Details

## Source

S154 / Chapter 70 / `BASELINE Statement` (PDF pp. 5214–5217); S154 / Chapter 70 / `Model and Likelihood` (PDF pp. 5229–5231); S154 / Chapter 70 / `Computational Details` (PDF pp. 5233–5235).

## Scope

Implement BASELINE; Model and Likelihood; Computational Details. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For BASELINE / Model and Likelihood / Computational Details, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 70.2: Plotting Predicted Survival and Cumulative Hazard Functions; explicit statements: BASELINE |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: BASELINE. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
