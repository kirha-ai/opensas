# STAT-TTEST-003 — TTEST — Arithmetic and Geometric Means / Coefficient of Variation

## Source

S154 / Chapter 128 / `Arithmetic and Geometric Means` (PDF p. 10620); S154 / Chapter 128 / `Coefficient of Variation` (PDF p. 10620).

## Scope

Implement Arithmetic and Geometric Means; Coefficient of Variation. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Arithmetic and Geometric Means / Coefficient of Variation, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [normal_lognormal.sas](normal_lognormal.sas) | captured | 0 | [listing](normal_lognormal.expected.txt) / [log](normal_lognormal.oracle.log) | Arithmetic versus geometric mean and coefficient-of-variation output |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
