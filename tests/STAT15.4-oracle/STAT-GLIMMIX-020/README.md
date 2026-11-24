# STAT-GLIMMIX-020 — GLIMMIX — CONTRAST / COVTEST / ESTIMATE

## Source

S154 / Chapter 52 / `CONTRAST Statement` (PDF pp. 3732–3736); S154 / Chapter 52 / `COVTEST Statement` (PDF pp. 3736–3744); S154 / Chapter 52 / `ESTIMATE Statement` (PDF pp. 3744–3750).

## Scope

Implement CONTRAST; COVTEST; ESTIMATE. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For CONTRAST / COVTEST / ESTIMATE, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 52.13: Response Surface Comparisons with Multiplicity Adjustments; explicit statements: CONTRAST, COVTEST, ESTIMATE |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: CONTRAST, COVTEST, ESTIMATE. Remaining statement variants: . Restored the complete contrast macro from physical PDF page 3999, using nine grid points for a smaller multiplicity fixture.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
