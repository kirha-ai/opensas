# STAT-SURVEYSELECT-001 — SURVEYSELECT — Data input, variable roles, and basic options

## Source

S154 / Chapter 124 / `PROC SURVEYSELECT Statement` (PDF pp. 10212–10235); S154 / Chapter 124 / `FREQ Statement` (PDF pp. 10235–10236); S154 / Chapter 124 / `ID Statement` (PDF p. 10236); S154 / Chapter 124 / `SIZE Statement` (PDF pp. 10237–10238); S154 / Chapter 124 / `STRATA Statement` (PDF pp. 10238–10243); S154 / Chapter 124 / `Missing Values` (PDF pp. 10243–10244); S154 / Chapter 124 / `Secondary Input Data Set` (PDF pp. 10260–10261).

## Scope

Integrate PROC SURVEYSELECT declarations, basic options, defaults, and execution boundaries; this ticket establishes parameter objects and result interfaces, while later feature tickets implement model-, algorithm-, and output-specific options. Also implement FREQ; ID; SIZE; STRATA; Missing Values; Secondary Input Data Set; apply this procedure's rules for missing values, variable roles, and observation selection.

## Acceptance criteria

Create positive and negative parsing cases for the documented declarations and basic options; verify defaults, explicit settings, documented duplicate/conflicting declarations, and locations; valid but unimplemented features must not silently succeed. For FREQ / ID / SIZE / STRATA / Missing Values / Secondary Input Data Set, construct valid, missing, empty, and multiple-group inputs; verify included observation counts, variable roles, BY boundaries, level ordering, and the frequency/weight rules relevant to this ticket; assert documented invalid-input behavior.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context; explicit statements: ID, SIZE, STRATA |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: ID, SIZE, STRATA. Remaining statement variants: FREQ.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
