# STAT-REG-001 — REG — Data input, variable roles, and basic options

## Source

S154 / Chapter 105 / `PROC REG Statement` (PDF pp. 8560–8574); S154 / Chapter 105 / `BY Statement` (PDF pp. 8574–8575); S154 / Chapter 105 / `FREQ Statement` (PDF p. 8576); S154 / Chapter 105 / `ID Statement` (PDF p. 8576); S154 / Chapter 105 / `VAR Statement` (PDF pp. 8599–8600); S154 / Chapter 105 / `WEIGHT Statement` (PDF p. 8600); S154 / Chapter 105 / `Missing Values` (PDF p. 8600); S154 / Chapter 105 / `Input Data Sets` (PDF pp. 8600–8603).

## Scope

Integrate PROC REG declarations, basic options, defaults, and execution boundaries; this ticket establishes parameter objects and result interfaces, while later feature tickets implement model-, algorithm-, and output-specific options. Also implement BY; FREQ; ID; VAR; WEIGHT; Missing Values; Input Data Sets; apply this procedure's rules for missing values, variable roles, and observation selection.

## Acceptance criteria

Create positive and negative parsing cases for the documented declarations and basic options; verify defaults, explicit settings, documented duplicate/conflicting declarations, and locations; valid but unimplemented features must not silently succeed. For BY / FREQ / ID / VAR / WEIGHT / Missing Values / Input Data Sets, construct valid, missing, empty, and multiple-group inputs; verify included observation counts, variable roles, BY boundaries, level ordering, and the frequency/weight rules relevant to this ticket; assert documented invalid-input behavior.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context; explicit statements: VAR, WEIGHT |
| [statement_by.sas](statement_by.sas) | captured | 1 | [listing](statement_by.expected.txt) / [log](statement_by.oracle.log) | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: VAR, WEIGHT. Remaining statement variants: BY, FREQ, ID.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
