# STAT-POWER-003 — POWER — COXREG / CUSTOM / LOGISTIC

## Source

S154 / Chapter 96 / `COXREG Statement` (PDF pp. 7746–7750); S154 / Chapter 96 / `CUSTOM Statement` (PDF pp. 7750–7756); S154 / Chapter 96 / `LOGISTIC Statement` (PDF pp. 7756–7763).

## Scope

Implement COXREG; CUSTOM; LOGISTIC. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For COXREG / CUSTOM / LOGISTIC, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 96.11: Logistic Regression Using the CUSTOM Statement; explicit statements: CUSTOM, LOGISTIC |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: CUSTOM, LOGISTIC. Remaining statement variants: COXREG.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
