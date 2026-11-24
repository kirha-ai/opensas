# STAT-CAUSALMED-005 — CAUSALMED — STD / Causal Mediation Effects: Definitions, Assumptions, and Identification / Evaluating Causal Mediation Effects

## Source

S154 / Chapter 38 / `STD Statement` (PDF pp. 2390–2391); S154 / Chapter 38 / `Causal Mediation Effects: Definitions, Assumptions, and Identification` (PDF pp. 2392–2400); S154 / Chapter 38 / `Evaluating Causal Mediation Effects` (PDF pp. 2400–2406).

## Scope

Implement STD; Causal Mediation Effects: Definitions, Assumptions, and Identification; Evaluating Causal Mediation Effects. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For STD / Causal Mediation Effects: Definitions, Assumptions, and Identification / Evaluating Causal Mediation Effects, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: STD.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
