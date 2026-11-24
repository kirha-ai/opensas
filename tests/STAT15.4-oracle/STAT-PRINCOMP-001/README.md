# STAT-PRINCOMP-001 — PRINCOMP — Data input, variable roles, and basic options

## Source

S154 / Chapter 98 / `PROC PRINCOMP Statement` (PDF pp. 7999–8005); S154 / Chapter 98 / `BY Statement` (PDF p. 8005); S154 / Chapter 98 / `FREQ Statement` (PDF pp. 8005–8006); S154 / Chapter 98 / `ID Statement` (PDF p. 8006); S154 / Chapter 98 / `VAR Statement` (PDF p. 8006); S154 / Chapter 98 / `WEIGHT Statement` (PDF pp. 8006–8007); S154 / Chapter 98 / `Missing Values` (PDF p. 8007).

## Scope

Integrate PROC PRINCOMP declarations, basic options, defaults, and execution boundaries; this ticket establishes parameter objects and result interfaces, while later feature tickets implement model-, algorithm-, and output-specific options. Also implement BY; FREQ; ID; VAR; WEIGHT; Missing Values; apply this procedure's rules for missing values, variable roles, and observation selection.

## Acceptance criteria

Create positive and negative parsing cases for the documented declarations and basic options; verify defaults, explicit settings, documented duplicate/conflicting declarations, and locations; valid but unimplemented features must not silently succeed. For BY / FREQ / ID / VAR / WEIGHT / Missing Values, construct valid, missing, empty, and multiple-group inputs; verify included observation counts, variable roles, BY boundaries, level ordering, and the frequency/weight rules relevant to this ticket; assert documented invalid-input behavior.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context; explicit statements: BY, ID |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: BY, ID. Remaining statement variants: FREQ, VAR, WEIGHT.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
