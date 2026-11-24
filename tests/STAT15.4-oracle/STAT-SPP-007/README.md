# STAT-SPP-007 — SPP — Fit Statistics / Fitted Model Validation That Uses Goodness-of-Fit Tests / Negative Binomial Modeling

## Source

S154 / Chapter 114 / `Fit Statistics` (PDF p. 9421); S154 / Chapter 114 / `Fitted Model Validation That Uses Goodness-of-Fit Tests` (PDF p. 9421); S154 / Chapter 114 / `Negative Binomial Modeling` (PDF p. 9423).

## Scope

Implement Fit Statistics; Fitted Model Validation That Uses Goodness-of-Fit Tests; Negative Binomial Modeling. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Fit Statistics / Fitted Model Validation That Uses Goodness-of-Fit Tests / Negative Binomial Modeling, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: SPP Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
