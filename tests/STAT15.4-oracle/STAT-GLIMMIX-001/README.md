# STAT-GLIMMIX-001 — GLIMMIX — Data input, variable roles, and basic options

## Source

S154 / Chapter 52 / `PROC GLIMMIX Statement` (PDF pp. 3703–3730); S154 / Chapter 52 / `BY Statement` (PDF pp. 3730–3731); S154 / Chapter 52 / `FREQ Statement` (PDF p. 3750); S154 / Chapter 52 / `ID Statement` (PDF pp. 3750–3751); S154 / Chapter 52 / `WEIGHT Statement` (PDF p. 3817); S154 / Chapter 52 / `Missing Level Combinations` (PDF p. 3876).

## Scope

Integrate PROC GLIMMIX declarations, basic options, defaults, and execution boundaries; this ticket establishes parameter objects and result interfaces, while later feature tickets implement model-, algorithm-, and output-specific options. Also implement BY; FREQ; ID; WEIGHT; Missing Level Combinations; apply this procedure's rules for missing values, variable roles, and observation selection.

## Acceptance criteria

Create positive and negative parsing cases for the documented declarations and basic options; verify defaults, explicit settings, documented duplicate/conflicting declarations, and locations; valid but unimplemented features must not silently succeed. For BY / FREQ / ID / WEIGHT / Missing Level Combinations, construct valid, missing, empty, and multiple-group inputs; verify included observation counts, variable roles, BY boundaries, level ordering, and the frequency/weight rules relevant to this ticket; assert documented invalid-input behavior.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context |
| [statement_by.sas](statement_by.sas) | captured | 0 | [listing](statement_by.expected.txt) / [log](statement_by.oracle.log) | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: none explicitly identified. Remaining statement variants: BY, FREQ, ID, WEIGHT.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
