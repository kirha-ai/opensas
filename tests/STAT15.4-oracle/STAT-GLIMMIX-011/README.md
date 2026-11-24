# STAT-GLIMMIX-011 — GLIMMIX — Maximum Likelihood / Scale and Dispersion Parameters / Quasi-likelihood for Independent Data

## Source

S154 / Chapter 52 / `Maximum Likelihood` (PDF pp. 3823–3826); S154 / Chapter 52 / `Scale and Dispersion Parameters` (PDF pp. 3826–3827); S154 / Chapter 52 / `Quasi-likelihood for Independent Data` (PDF pp. 3827–3828).

## Scope

Implement Maximum Likelihood; Scale and Dispersion Parameters; Quasi-likelihood for Independent Data. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Maximum Likelihood / Scale and Dispersion Parameters / Quasi-likelihood for Independent Data, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 52.4: Quasi-likelihood Estimation for Proportions with Unknown Distribution |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
