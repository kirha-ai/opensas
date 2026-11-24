# STAT-PHREG-008 — PHREG — Newton-Raphson Method / Firth's Modification for Maximum Likelihood Estimation / Robust Sandwich Variance Estimate

## Source

S154 / Chapter 92 / `Newton-Raphson Method` (PDF p. 7412); S154 / Chapter 92 / `Firth's Modification for Maximum Likelihood Estimation` (PDF pp. 7412–7414); S154 / Chapter 92 / `Robust Sandwich Variance Estimate` (PDF p. 7414).

## Scope

Implement Newton-Raphson Method; Firth's Modification for Maximum Likelihood Estimation; Robust Sandwich Variance Estimate. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Newton-Raphson Method / Firth's Modification for Maximum Likelihood Estimation / Robust Sandwich Variance Estimate, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 92.4: Firth's Correction for Monotone Likelihood |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
