# STAT-CAUSALTRT-004 — CAUSALTRT — Causal Effects: Definitions, Assumptions, and Identification / Estimating the Average Treatment Effect (ATE) / Estimating the Average Treatment Effect for the Treated (ATT)

## Source

S154 / Chapter 39 / `Causal Effects: Definitions, Assumptions, and Identification` (PDF pp. 2459–2462); S154 / Chapter 39 / `Estimating the Average Treatment Effect (ATE)` (PDF pp. 2462–2467); S154 / Chapter 39 / `Estimating the Average Treatment Effect for the Treated (ATT)` (PDF pp. 2467–2469).

## Scope

Implement Causal Effects: Definitions, Assumptions, and Identification; Estimating the Average Treatment Effect (ATE); Estimating the Average Treatment Effect for the Treated (ATT). This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Causal Effects: Definitions, Assumptions, and Identification / Estimating the Average Treatment Effect (ATE) / Estimating the Average Treatment Effect for the Treated (ATT), use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: CAUSALTRT Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
