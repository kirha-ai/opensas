# STAT-LIFEREG-004 — LIFEREG — PROBPLOT / Model Specification / Computational Method

## Source

S154 / Chapter 76 / `PROBPLOT Statement` (PDF pp. 5561–5565); S154 / Chapter 76 / `Model Specification` (PDF pp. 5566–5567); S154 / Chapter 76 / `Computational Method` (PDF pp. 5567–5569).

## Scope

Implement PROBPLOT; Model Specification; Computational Method. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For PROBPLOT / Model Specification / Computational Method, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 76.6: Probability Plotting—Arbitrary Censoring; explicit statements: PROBPLOT |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: PROBPLOT. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
