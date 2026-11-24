# STAT-SURVEYREG-012 — SURVEYREG — CONTRAST / ESTIMATE / TEST

## Source

S154 / Chapter 123 / `CONTRAST Statement` (PDF pp. 10127–10128); S154 / Chapter 123 / `ESTIMATE Statement` (PDF pp. 10130–10131); S154 / Chapter 123 / `TEST Statement` (PDF pp. 10140–10141).

## Scope

Implement CONTRAST; ESTIMATE; TEST. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For CONTRAST / ESTIMATE / TEST, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 123.9: Variance Estimate Using the Jackknife Method; explicit statements: ESTIMATE |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: ESTIMATE. Remaining statement variants: CONTRAST, TEST. Restored the official grade-specific inverse inclusion weights established earlier in the chapter.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
