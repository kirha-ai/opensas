# STAT-SURVEYLOGISTIC-001 — SURVEYLOGISTIC — Data input, variable roles, and basic options

## Source

S154 / Chapter 120 / `PROC SURVEYLOGISTIC Statement` (PDF pp. 9803–9811); S154 / Chapter 120 / `BY Statement` (PDF pp. 9811–9812); S154 / Chapter 120 / `CLUSTER Statement` (PDF p. 9814); S154 / Chapter 120 / `FREQ Statement` (PDF p. 9820); S154 / Chapter 120 / `REPWEIGHTS Statement` (PDF pp. 9834–9836); S154 / Chapter 120 / `STRATA Statement` (PDF p. 9837); S154 / Chapter 120 / `WEIGHT Statement` (PDF p. 9839); S154 / Chapter 120 / `Missing Values` (PDF pp. 9839–9840).

## Scope

Integrate PROC SURVEYLOGISTIC declarations, basic options, defaults, and execution boundaries; this ticket establishes parameter objects and result interfaces, while later feature tickets implement model-, algorithm-, and output-specific options. Also implement BY; CLUSTER; FREQ; REPWEIGHTS; STRATA; WEIGHT; Missing Values; apply this procedure's rules for missing values, variable roles, and observation selection.

## Acceptance criteria

Create positive and negative parsing cases for the documented declarations and basic options; verify defaults, explicit settings, documented duplicate/conflicting declarations, and locations; valid but unimplemented features must not silently succeed. For BY / CLUSTER / FREQ / REPWEIGHTS / STRATA / WEIGHT / Missing Values, construct valid, missing, empty, and multiple-group inputs; verify included observation counts, variable roles, BY boundaries, level ordering, and the frequency/weight rules relevant to this ticket; assert documented invalid-input behavior.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context; explicit statements: CLUSTER, STRATA, WEIGHT |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: CLUSTER, STRATA, WEIGHT. Remaining statement variants: BY, FREQ, REPWEIGHTS.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
