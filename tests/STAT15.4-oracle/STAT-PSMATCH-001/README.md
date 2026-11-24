# STAT-PSMATCH-001 — PSMATCH — Data input, variable roles, and basic options

## Source

S154 / Chapter 101 / `PROC PSMATCH Statement` (PDF pp. 8214–8217); S154 / Chapter 101 / `BY Statement` (PDF pp. 8222–8223); S154 / Chapter 101 / `CLASS Statement` (PDF p. 8223); S154 / Chapter 101 / `FREQ Statement` (PDF p. 8223); S154 / Chapter 101 / `ID Statement` (PDF p. 8223); S154 / Chapter 101 / `STRATA Statement` (PDF pp. 8234–8235); S154 / Chapter 101 / `Weighting after Stratification` (PDF pp. 8243–8244); S154 / Chapter 101 / `Weighting after Matching` (PDF pp. 8248–8250).

## Scope

Integrate PROC PSMATCH declarations, basic options, defaults, and execution boundaries; this ticket establishes parameter objects and result interfaces, while later feature tickets implement model-, algorithm-, and output-specific options. Also implement BY; CLASS; FREQ; ID; STRATA; Weighting after Stratification; Weighting after Matching; apply this procedure's rules for missing values, variable roles, and observation selection.

## Acceptance criteria

Create positive and negative parsing cases for the documented declarations and basic options; verify defaults, explicit settings, documented duplicate/conflicting declarations, and locations; valid but unimplemented features must not silently succeed. For BY / CLASS / FREQ / ID / STRATA / Weighting after Stratification / Weighting after Matching, construct valid, missing, empty, and multiple-group inputs; verify included observation counts, variable roles, BY boundaries, level ordering, and the frequency/weight rules relevant to this ticket; assert documented invalid-input behavior.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context; explicit statements: CLASS |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: CLASS. Remaining statement variants: BY, FREQ, ID, STRATA.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
