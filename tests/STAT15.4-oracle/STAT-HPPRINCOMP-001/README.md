# STAT-HPPRINCOMP-001 — HPPRINCOMP — Data input, variable roles, and basic options

## Source

S154 / Chapter 65 / `PROC HPPRINCOMP Statement` (PDF pp. 4950–4954); S154 / Chapter 65 / `BY Statement` (PDF pp. 4954–4955); S154 / Chapter 65 / `FREQ Statement` (PDF pp. 4955–4956); S154 / Chapter 65 / `ID Statement` (PDF p. 4956); S154 / Chapter 65 / `VAR Statement` (PDF p. 4958); S154 / Chapter 65 / `WEIGHT Statement` (PDF p. 4958); S154 / Chapter 65 / `Missing Values` (PDF pp. 4959–4960).

## Scope

Integrate PROC HPPRINCOMP declarations, basic options, defaults, and execution boundaries; this ticket establishes parameter objects and result interfaces, while later feature tickets implement model-, algorithm-, and output-specific options. Also implement BY; FREQ; ID; VAR; WEIGHT; Missing Values; apply this procedure's rules for missing values, variable roles, and observation selection.

## Acceptance criteria

Create positive and negative parsing cases for the documented declarations and basic options; verify defaults, explicit settings, documented duplicate/conflicting declarations, and locations; valid but unimplemented features must not silently succeed. For BY / FREQ / ID / VAR / WEIGHT / Missing Values, construct valid, missing, empty, and multiple-group inputs; verify included observation counts, variable roles, BY boundaries, level ordering, and the frequency/weight rules relevant to this ticket; assert documented invalid-input behavior.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context; explicit statements: BY |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: BY. Remaining statement variants: FREQ, ID, VAR, WEIGHT. Converted state labels to underscore-separated list input, preserving the official missing Murder value for Wyoming.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
