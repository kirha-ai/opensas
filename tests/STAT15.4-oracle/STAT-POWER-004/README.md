# STAT-POWER-004 — POWER — MULTREG / ONECORR / ONESAMPLEFREQ

## Source

S154 / Chapter 96 / `MULTREG Statement` (PDF pp. 7763–7768); S154 / Chapter 96 / `ONECORR Statement` (PDF pp. 7768–7772); S154 / Chapter 96 / `ONESAMPLEFREQ Statement` (PDF pp. 7772–7780).

## Scope

Implement MULTREG; ONECORR; ONESAMPLEFREQ. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For MULTREG / ONECORR / ONESAMPLEFREQ, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 96.5: Multiple Regression and Correlation; explicit statements: MULTREG, ONECORR |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: MULTREG, ONECORR. Remaining statement variants: ONESAMPLEFREQ.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
