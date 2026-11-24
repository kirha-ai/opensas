# STAT-SURVEYREG-001 — SURVEYREG — Data input, variable roles, and basic options

## Source

S154 / Chapter 123 / `PROC SURVEYREG Statement` (PDF pp. 10113–10124); S154 / Chapter 123 / `BY Statement` (PDF pp. 10124–10125); S154 / Chapter 123 / `CLUSTER Statement` (PDF pp. 10126–10127); S154 / Chapter 123 / `REPWEIGHTS Statement` (PDF pp. 10137–10139); S154 / Chapter 123 / `STRATA Statement` (PDF p. 10140); S154 / Chapter 123 / `WEIGHT Statement` (PDF pp. 10141–10142); S154 / Chapter 123 / `Missing Values` (PDF pp. 10142–10143).

## Scope

Integrate PROC SURVEYREG declarations, basic options, defaults, and execution boundaries; this ticket establishes parameter objects and result interfaces, while later feature tickets implement model-, algorithm-, and output-specific options. Also implement BY; CLUSTER; REPWEIGHTS; STRATA; WEIGHT; Missing Values; apply this procedure's rules for missing values, variable roles, and observation selection.

## Acceptance criteria

Create positive and negative parsing cases for the documented declarations and basic options; verify defaults, explicit settings, documented duplicate/conflicting declarations, and locations; valid but unimplemented features must not silently succeed. For BY / CLUSTER / REPWEIGHTS / STRATA / WEIGHT / Missing Values, construct valid, missing, empty, and multiple-group inputs; verify included observation counts, variable roles, BY boundaries, level ordering, and the frequency/weight rules relevant to this ticket; assert documented invalid-input behavior.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context; explicit statements: STRATA, WEIGHT |
| [statement_by.sas](statement_by.sas) | captured | 1 | [listing](statement_by.expected.txt) / [log](statement_by.oracle.log) | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: STRATA, WEIGHT. Remaining statement variants: BY, CLUSTER, REPWEIGHTS.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
