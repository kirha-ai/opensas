# STAT-TRANSREG-007 — TRANSREG — Controlling the Number of Iterations / Using the REITERATE Algorithm Option / Avoiding Constant Transformations

## Source

S154 / Chapter 126 / `Controlling the Number of Iterations` (PDF pp. 10476–10477); S154 / Chapter 126 / `Using the REITERATE Algorithm Option` (PDF pp. 10477–10478); S154 / Chapter 126 / `Avoiding Constant Transformations` (PDF pp. 10478–10479).

## Scope

Implement Controlling the Number of Iterations; Using the REITERATE Algorithm Option; Avoiding Constant Transformations. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Controlling the Number of Iterations / Using the REITERATE Algorithm Option / Avoiding Constant Transformations, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 126.2: Box-Cox Transformations |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
