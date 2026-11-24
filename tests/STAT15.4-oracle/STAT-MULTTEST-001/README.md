# STAT-MULTTEST-001 — MULTTEST — Data input, variable roles, and basic options

## Source

S154 / Chapter 86 / `PROC MULTTEST Statement` (PDF pp. 6897–6909); S154 / Chapter 86 / `BY Statement` (PDF p. 6909); S154 / Chapter 86 / `CLASS Statement` (PDF pp. 6909–6910); S154 / Chapter 86 / `FREQ Statement` (PDF p. 6911); S154 / Chapter 86 / `ID Statement` (PDF pp. 6911–6912); S154 / Chapter 86 / `STRATA Statement` (PDF p. 6912); S154 / Chapter 86 / `Missing Values` (PDF p. 6930).

## Scope

Integrate PROC MULTTEST declarations, basic options, defaults, and execution boundaries; this ticket establishes parameter objects and result interfaces, while later feature tickets implement model-, algorithm-, and output-specific options. Also implement BY; CLASS; FREQ; ID; STRATA; Missing Values; apply this procedure's rules for missing values, variable roles, and observation selection.

## Acceptance criteria

Create positive and negative parsing cases for the documented declarations and basic options; verify defaults, explicit settings, documented duplicate/conflicting declarations, and locations; valid but unimplemented features must not silently succeed. For BY / CLASS / FREQ / ID / STRATA / Missing Values, construct valid, missing, empty, and multiple-group inputs; verify included observation counts, variable roles, BY boundaries, level ordering, and the frequency/weight rules relevant to this ticket; assert documented invalid-input behavior.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context; explicit statements: CLASS |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: CLASS. Remaining statement variants: BY, FREQ, ID, STRATA.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
