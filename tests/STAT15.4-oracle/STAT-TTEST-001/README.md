# STAT-TTEST-001 — TTEST — Data input, variable roles, and basic options

## Source

S154 / Chapter 128 / `PROC TTEST Statement` (PDF pp. 10604–10613); S154 / Chapter 128 / `BY Statement` (PDF pp. 10615–10616); S154 / Chapter 128 / `CLASS Statement` (PDF p. 10616); S154 / Chapter 128 / `FREQ Statement` (PDF pp. 10616–10617); S154 / Chapter 128 / `VAR Statement` (PDF pp. 10617–10618); S154 / Chapter 128 / `WEIGHT Statement` (PDF p. 10618); S154 / Chapter 128 / `Input Data Set of Statistics` (PDF pp. 10618–10619); S154 / Chapter 128 / `Missing Values` (PDF p. 10619).

## Scope

Integrate PROC TTEST declarations, basic options, defaults, and execution boundaries; this ticket establishes parameter objects and result interfaces, while later feature tickets implement model-, algorithm-, and output-specific options. Also implement BY; CLASS; FREQ; VAR; WEIGHT; Input Data Set of Statistics; Missing Values; apply this procedure's rules for missing values, variable roles, and observation selection.

## Acceptance criteria

Create positive and negative parsing cases for the documented declarations and basic options; verify defaults, explicit settings, documented duplicate/conflicting declarations, and locations; valid but unimplemented features must not silently succeed. For BY / CLASS / FREQ / VAR / WEIGHT / Input Data Set of Statistics / Missing Values, construct valid, missing, empty, and multiple-group inputs; verify included observation counts, variable roles, BY boundaries, level ordering, and the frequency/weight rules relevant to this ticket; assert documented invalid-input behavior.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [by_frequency_weight.sas](by_frequency_weight.sas) | captured | 0 | [listing](by_frequency_weight.expected.txt) / [log](by_frequency_weight.oracle.log) | BY boundaries, multiple VAR roles, frequency versus analysis weights, and explicit input data |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
