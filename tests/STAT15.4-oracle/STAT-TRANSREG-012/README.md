# STAT-TRANSREG-012 — TRANSREG — Unbalanced ANOVA without CLASS Variables / Using the DESIGN Output Option / Discrete Choice Experiments: DESIGN, NORESTORE, NOZERO

## Source

S154 / Chapter 126 / `Unbalanced ANOVA without CLASS Variables` (PDF pp. 10501–10502); S154 / Chapter 126 / `Using the DESIGN Output Option` (PDF pp. 10515–10519); S154 / Chapter 126 / `Discrete Choice Experiments: DESIGN, NORESTORE, NOZERO` (PDF pp. 10519–10520).

## Scope

Implement Unbalanced ANOVA without CLASS Variables; Using the DESIGN Output Option; Discrete Choice Experiments: DESIGN, NORESTORE, NOZERO. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Unbalanced ANOVA without CLASS Variables / Using the DESIGN Output Option / Discrete Choice Experiments: DESIGN, NORESTORE, NOZERO, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: TRANSREG Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
