# STAT-MIANALYZE-003 — MIANALYZE — MODELEFFECTS / STDERR / Combining Inferences from Imputed Data Sets

## Source

S154 / Chapter 83 / `MODELEFFECTS Statement` (PDF p. 6564); S154 / Chapter 83 / `STDERR Statement` (PDF pp. 6564–6565); S154 / Chapter 83 / `Combining Inferences from Imputed Data Sets` (PDF pp. 6571–6572).

## Scope

Implement MODELEFFECTS; STDERR; Combining Inferences from Imputed Data Sets. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For MODELEFFECTS / STDERR / Combining Inferences from Imputed Data Sets, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: MIANALYZE Procedure; explicit statements: MODELEFFECTS |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: MODELEFFECTS. Remaining statement variants: STDERR.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
