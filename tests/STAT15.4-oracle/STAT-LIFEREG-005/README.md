# STAT-LIFEREG-005 — LIFEREG — Supported Distributions / Fit Statistics / INEST= Data Set

## Source

S154 / Chapter 76 / `Supported Distributions` (PDF pp. 5569–5572); S154 / Chapter 76 / `Fit Statistics` (PDF pp. 5575–5576); S154 / Chapter 76 / `INEST= Data Set` (PDF p. 5581).

## Scope

Implement Supported Distributions; Fit Statistics; INEST= Data Set. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Supported Distributions / Fit Statistics / INEST= Data Set, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: LIFEREG Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
