# STAT-PROBIT-004 — PROBIT — Computational Method / Distributions / INEST= SAS-data-set

## Source

S154 / Chapter 100 / `Computational Method` (PDF pp. 8122–8123); S154 / Chapter 100 / `Distributions` (PDF pp. 8123–8124); S154 / Chapter 100 / `INEST= SAS-data-set` (PDF p. 8124).

## Scope

Implement Computational Method; Distributions; INEST= SAS-data-set. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Computational Method / Distributions / INEST= SAS-data-set, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: PROBIT Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
