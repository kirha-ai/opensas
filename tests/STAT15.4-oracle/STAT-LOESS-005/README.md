# STAT-LOESS-005 — LOESS — Local Weighting / Iterative Reweighting / Specifying the Local Polynomials

## Source

S154 / Chapter 78 / `Local Weighting` (PDF p. 5788); S154 / Chapter 78 / `Iterative Reweighting` (PDF pp. 5788–5789); S154 / Chapter 78 / `Specifying the Local Polynomials` (PDF p. 5789).

## Scope

Implement Local Weighting; Iterative Reweighting; Specifying the Local Polynomials. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Local Weighting / Iterative Reweighting / Specifying the Local Polynomials, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: LOESS Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
