# STAT-HPQUANTSELECT-005 — HPQUANTSELECT — Quasi-likelihood Information Criteria / Statistical Tests for Significance Level / Classification Variables and the SPLIT Option

## Source

S154 / Chapter 66 / `Quasi-likelihood Information Criteria` (PDF pp. 4999–5000); S154 / Chapter 66 / `Statistical Tests for Significance Level` (PDF pp. 5000–5002); S154 / Chapter 66 / `Classification Variables and the SPLIT Option` (PDF pp. 5002–5003).

## Scope

Implement Quasi-likelihood Information Criteria; Statistical Tests for Significance Level; Classification Variables and the SPLIT Option. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Quasi-likelihood Information Criteria / Statistical Tests for Significance Level / Classification Variables and the SPLIT Option, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Seeded synthetic quantile-regression fixture: Quasi-likelihood Information Criteria / Statistical Tests for Significance Level / Classification Variables and the SPLIT Option |

**documented_feature:** Bounded adaptation of the documented syntax using 120 explicit seeded synthetic rows and three numeric covariates. It replaces the slow four-fit baseball illustration and preserves this ticket’s targeted behavior.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
