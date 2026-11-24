# STAT-FACTOR-006 — FACTOR — Confidence Intervals and the Salience of Factor Loadings

## Source

S154 / Chapter 44 / `Confidence Intervals and the Salience of Factor Loadings` (PDF pp. 2831–2832).

## Scope

Implement Confidence Intervals and the Salience of Factor Loadings. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Confidence Intervals and the Salience of Factor Loadings, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 44.5: Using Confidence Intervals to Locate Salient Factor Loadings |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
