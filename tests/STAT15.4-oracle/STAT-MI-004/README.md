# STAT-MI-004 — MI — MONOTONE / TRANSFORM / Descriptive Statistics

## Source

S154 / Chapter 82 / `MONOTONE Statement` (PDF pp. 6443–6447); S154 / Chapter 82 / `TRANSFORM Statement` (PDF pp. 6447–6448); S154 / Chapter 82 / `Descriptive Statistics` (PDF pp. 6449–6450).

## Scope

Implement MONOTONE; TRANSFORM; Descriptive Statistics. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For MONOTONE / TRANSFORM / Descriptive Statistics, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 82.10: Producing Monotone Missingness with MCMC; explicit statements: MONOTONE |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: MONOTONE. Remaining statement variants: TRANSFORM.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
