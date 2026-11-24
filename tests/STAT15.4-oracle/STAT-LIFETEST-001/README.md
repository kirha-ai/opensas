# STAT-LIFETEST-001 — LIFETEST — Data input, variable roles, and basic options

## Source

S154 / Chapter 77 / `PROC LIFETEST Statement` (PDF pp. 5650–5662); S154 / Chapter 77 / `BY Statement` (PDF pp. 5662–5663); S154 / Chapter 77 / `FREQ Statement` (PDF p. 5663); S154 / Chapter 77 / `ID Statement` (PDF p. 5663); S154 / Chapter 77 / `STRATA Statement` (PDF pp. 5663–5668); S154 / Chapter 77 / `WEIGHT Statement` (PDF p. 5670); S154 / Chapter 77 / `Missing Values` (PDF pp. 5670–5671).

## Scope

Integrate PROC LIFETEST declarations, basic options, defaults, and execution boundaries; this ticket establishes parameter objects and result interfaces, while later feature tickets implement model-, algorithm-, and output-specific options. Also implement BY; FREQ; ID; STRATA; WEIGHT; Missing Values; apply this procedure's rules for missing values, variable roles, and observation selection.

## Acceptance criteria

Create positive and negative parsing cases for the documented declarations and basic options; verify defaults, explicit settings, documented duplicate/conflicting declarations, and locations; valid but unimplemented features must not silently succeed. For BY / FREQ / ID / STRATA / WEIGHT / Missing Values, construct valid, missing, empty, and multiple-group inputs; verify included observation counts, variable roles, BY boundaries, level ordering, and the frequency/weight rules relevant to this ticket; assert documented invalid-input behavior.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context; explicit statements: STRATA |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: STRATA. Remaining statement variants: BY, FREQ, ID, WEIGHT.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
