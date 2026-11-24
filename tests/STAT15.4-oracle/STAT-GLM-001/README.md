# STAT-GLM-001 — GLM — Data input, variable roles, and basic options

## Source

S154 / Chapter 53 / `PROC GLM Statement` (PDF pp. 4058–4065); S154 / Chapter 53 / `BY Statement` (PDF pp. 4065–4066); S154 / Chapter 53 / `FREQ Statement` (PDF pp. 4071–4072); S154 / Chapter 53 / `ID Statement` (PDF p. 4072); S154 / Chapter 53 / `WEIGHT Statement` (PDF p. 4106); S154 / Chapter 53 / `Missing Values` (PDF pp. 4160–4161).

## Scope

Integrate PROC GLM declarations, basic options, defaults, and execution boundaries; this ticket establishes parameter objects and result interfaces, while later feature tickets implement model-, algorithm-, and output-specific options. Also implement BY; FREQ; ID; WEIGHT; Missing Values; apply this procedure's rules for missing values, variable roles, and observation selection.

## Acceptance criteria

Create positive and negative parsing cases for the documented declarations and basic options; verify defaults, explicit settings, documented duplicate/conflicting declarations, and locations; valid but unimplemented features must not silently succeed. For BY / FREQ / ID / WEIGHT / Missing Values, construct valid, missing, empty, and multiple-group inputs; verify included observation counts, variable roles, BY boundaries, level ordering, and the frequency/weight rules relevant to this ticket; assert documented invalid-input behavior.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context; explicit statements: BY |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: BY. Remaining statement variants: FREQ, ID, WEIGHT.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
