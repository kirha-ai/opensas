# STAT-SURVEYIMPUTE-001 — SURVEYIMPUTE — Data input, variable roles, and basic options

## Source

S154 / Chapter 119 / `PROC SURVEYIMPUTE Statement` (PDF pp. 9704–9713); S154 / Chapter 119 / `BY Statement` (PDF pp. 9713–9714); S154 / Chapter 119 / `CLASS Statement` (PDF pp. 9714–9715); S154 / Chapter 119 / `CLUSTER Statement` (PDF p. 9715); S154 / Chapter 119 / `ID Statement` (PDF pp. 9715–9716); S154 / Chapter 119 / `REPWEIGHTS Statement` (PDF pp. 9718–9719); S154 / Chapter 119 / `STRATA Statement` (PDF p. 9719); S154 / Chapter 119 / `VAR Statement` (PDF pp. 9719–9720); S154 / Chapter 119 / `WEIGHT Statement` (PDF p. 9720); S154 / Chapter 119 / `Missing Values` (PDF pp. 9723–9725); S154 / Chapter 119 / `Missing Data Patterns` (PDF p. 9725).

## Scope

Integrate PROC SURVEYIMPUTE declarations, basic options, defaults, and execution boundaries; this ticket establishes parameter objects and result interfaces, while later feature tickets implement model-, algorithm-, and output-specific options. Also implement BY; CLASS; CLUSTER; ID; REPWEIGHTS; STRATA; VAR; WEIGHT; Missing Values; Missing Data Patterns; apply this procedure's rules for missing values, variable roles, and observation selection.

## Acceptance criteria

Create positive and negative parsing cases for the documented declarations and basic options; verify defaults, explicit settings, documented duplicate/conflicting declarations, and locations; valid but unimplemented features must not silently succeed. For BY / CLASS / CLUSTER / ID / REPWEIGHTS / STRATA / VAR / WEIGHT / Missing Values / Missing Data Patterns, construct valid, missing, empty, and multiple-group inputs; verify included observation counts, variable roles, BY boundaries, level ordering, and the frequency/weight rules relevant to this ticket; assert documented invalid-input behavior.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context; explicit statements: CLASS, CLUSTER, REPWEIGHTS, STRATA, VAR, WEIGHT |
| [statement_by.sas](statement_by.sas) | captured | 0 | [listing](statement_by.expected.txt) / [log](statement_by.oracle.log) | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: CLASS, CLUSTER, REPWEIGHTS, STRATA, VAR, WEIGHT. Remaining statement variants: BY, ID.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
