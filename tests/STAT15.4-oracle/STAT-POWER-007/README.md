# STAT-POWER-007 — POWER — TWOSAMPLESURVIVAL / TWOSAMPLEWILCOXON / Overview of Power Concepts

## Source

S154 / Chapter 96 / `TWOSAMPLESURVIVAL Statement` (PDF pp. 7830–7842); S154 / Chapter 96 / `TWOSAMPLEWILCOXON Statement` (PDF pp. 7842–7847); S154 / Chapter 96 / `Overview of Power Concepts` (PDF pp. 7847–7848).

## Scope

Implement TWOSAMPLESURVIVAL; TWOSAMPLEWILCOXON; Overview of Power Concepts. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For TWOSAMPLESURVIVAL / TWOSAMPLEWILCOXON / Overview of Power Concepts, verify forward power calculations, inverse solutions, rounding, and feasible boundaries; substituting the returned value into the original problem must meet the documented accuracy; validate numerical values against the source formulas or an independent reference, following this file's precision conventions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 96.6: Comparing Two Survival Curves; explicit statements: TWOSAMPLESURVIVAL |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: TWOSAMPLESURVIVAL. Remaining statement variants: TWOSAMPLEWILCOXON.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
