# STAT-FREQ-016 — FREQ — TEST / Tests and Measures of Agreement

## Source

S154 / Chapter 47 / `TEST Statement` (PDF pp. 3154–3157); S154 / Chapter 47 / `Tests and Measures of Agreement` (PDF pp. 3216–3223).

## Scope

Implement TEST; Tests and Measures of Agreement. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For TEST / Tests and Measures of Agreement, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: FREQ Procedure; explicit statements: TEST |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: TEST. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
