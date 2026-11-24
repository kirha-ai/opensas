# STAT-STDIZE-001 — STDIZE — Data input, variable roles, and basic options

## Source

S154 / Chapter 115 / `PROC STDIZE Statement` (PDF pp. 9455–9461); S154 / Chapter 115 / `BY Statement` (PDF pp. 9461–9462); S154 / Chapter 115 / `FREQ Statement` (PDF p. 9462); S154 / Chapter 115 / `VAR Statement` (PDF pp. 9462–9463); S154 / Chapter 115 / `WEIGHT Statement` (PDF pp. 9463–9464); S154 / Chapter 115 / `Missing Values` (PDF p. 9469).

## Scope

Integrate PROC STDIZE declarations, basic options, defaults, and execution boundaries; this ticket establishes parameter objects and result interfaces, while later feature tickets implement model-, algorithm-, and output-specific options. Also implement BY; FREQ; VAR; WEIGHT; Missing Values; apply this procedure's rules for missing values, variable roles, and observation selection.

## Acceptance criteria

Create positive and negative parsing cases for the documented declarations and basic options; verify defaults, explicit settings, documented duplicate/conflicting declarations, and locations; valid but unimplemented features must not silently succeed. For BY / FREQ / VAR / WEIGHT / Missing Values, construct valid, missing, empty, and multiple-group inputs; verify included observation counts, variable roles, BY boundaries, level ordering, and the frequency/weight rules relevant to this ticket; assert documented invalid-input behavior.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context; explicit statements: BY, FREQ, VAR, WEIGHT |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: BY, FREQ, VAR, WEIGHT. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
