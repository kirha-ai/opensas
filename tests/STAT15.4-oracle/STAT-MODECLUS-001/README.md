# STAT-MODECLUS-001 — MODECLUS — Data input, variable roles, and basic options

## Source

S154 / Chapter 85 / `PROC MODECLUS Statement` (PDF pp. 6818–6825); S154 / Chapter 85 / `BY Statement` (PDF p. 6825); S154 / Chapter 85 / `FREQ Statement` (PDF pp. 6825–6826); S154 / Chapter 85 / `ID Statement` (PDF p. 6826); S154 / Chapter 85 / `VAR Statement` (PDF p. 6826); S154 / Chapter 85 / `Missing Values` (PDF pp. 6837–6838).

## Scope

Integrate PROC MODECLUS declarations, basic options, defaults, and execution boundaries; this ticket establishes parameter objects and result interfaces, while later feature tickets implement model-, algorithm-, and output-specific options. Also implement BY; FREQ; ID; VAR; Missing Values; apply this procedure's rules for missing values, variable roles, and observation selection.

## Acceptance criteria

Create positive and negative parsing cases for the documented declarations and basic options; verify defaults, explicit settings, documented duplicate/conflicting declarations, and locations; valid but unimplemented features must not silently succeed. For BY / FREQ / ID / VAR / Missing Values, construct valid, missing, empty, and multiple-group inputs; verify included observation counts, variable roles, BY boundaries, level ordering, and the frequency/weight rules relevant to this ticket; assert documented invalid-input behavior.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context; explicit statements: BY |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: BY. Remaining statement variants: FREQ, ID, VAR.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
