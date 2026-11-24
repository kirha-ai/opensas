# STAT-BCHOICE-004 — BCHOICE — Discrete Choice Models / Types of Choice Models / Other Types of Choice Response

## Source

S154 / Chapter 30 / `Discrete Choice Models` (PDF pp. 1202–1203); S154 / Chapter 30 / `Types of Choice Models` (PDF pp. 1203–1208); S154 / Chapter 30 / `Other Types of Choice Response` (PDF pp. 1211–1212).

## Scope

Implement Discrete Choice Models; Types of Choice Models; Other Types of Choice Response. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Discrete Choice Models / Types of Choice Models / Other Types of Choice Response, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 30.5: Heterogeneity Affected by Individual Characteristics |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
