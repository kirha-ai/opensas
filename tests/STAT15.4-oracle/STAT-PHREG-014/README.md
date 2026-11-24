# STAT-PHREG-014 — PHREG — Hazard Ratios / HAZARDRATIO / Confidence Limits for a Hazard Ratio

## Source

S154 / Chapter 92 / `Hazard Ratios` (PDF pp. 7409–7412); S154 / Chapter 92 / `HAZARDRATIO Statement` (PDF pp. 7364–7367); S154 / Chapter 92 / `Confidence Limits for a Hazard Ratio` (PDF pp. 7416–7418).

## Scope

Implement Hazard Ratios; HAZARDRATIO; Confidence Limits for a Hazard Ratio. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Hazard Ratios / HAZARDRATIO / Confidence Limits for a Hazard Ratio, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 92.13: Bayesian Analysis of the Cox Model; explicit statements: HAZARDRATIO |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: HAZARDRATIO. Remaining statement variants: . Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof. Restored the official yesno format and the missing terminator of the prior-input DATALINES.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
