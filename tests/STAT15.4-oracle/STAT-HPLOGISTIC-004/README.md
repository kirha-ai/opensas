# STAT-HPLOGISTIC-004 — HPLOGISTIC — Response Distributions / Log-Likelihood Functions / The Hosmer-Lemeshow Goodness-of-Fit Test

## Source

S154 / Chapter 61 / `Response Distributions` (PDF pp. 4765–4766); S154 / Chapter 61 / `Log-Likelihood Functions` (PDF pp. 4766–4767); S154 / Chapter 61 / `The Hosmer-Lemeshow Goodness-of-Fit Test` (PDF pp. 4774–4775).

## Scope

Implement Response Distributions; Log-Likelihood Functions; The Hosmer-Lemeshow Goodness-of-Fit Test. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Response Distributions / Log-Likelihood Functions / The Hosmer-Lemeshow Goodness-of-Fit Test, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: HPLOGISTIC Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
