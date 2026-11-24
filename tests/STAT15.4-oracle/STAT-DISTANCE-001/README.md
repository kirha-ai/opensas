# STAT-DISTANCE-001 — DISTANCE — Data input, variable roles, and basic options

## Source

S154 / Chapter 43 / `PROC DISTANCE Statement` (PDF pp. 2747–2754); S154 / Chapter 43 / `VAR Statement` (PDF pp. 2754–2759); S154 / Chapter 43 / `ID Statement` (PDF p. 2759); S154 / Chapter 43 / `COPY Statement` (PDF p. 2759); S154 / Chapter 43 / `BY Statement` (PDF pp. 2759–2760); S154 / Chapter 43 / `FREQ Statement` (PDF p. 2760); S154 / Chapter 43 / `WEIGHT Statement` (PDF pp. 2760–2761); S154 / Chapter 43 / `Missing Values` (PDF p. 2768); S154 / Chapter 43 / `Formatted versus Unformatted Values` (PDF pp. 2768–2769).

## Scope

Integrate PROC DISTANCE declarations, basic options, defaults, and execution boundaries; this ticket establishes parameter objects and result interfaces, while later feature tickets implement model-, algorithm-, and output-specific options. Also implement VAR; ID; COPY; BY; FREQ; WEIGHT; Missing Values; Formatted versus Unformatted Values; apply this procedure's rules for missing values, variable roles, and observation selection.

## Acceptance criteria

Create positive and negative parsing cases for the documented declarations and basic options; verify defaults, explicit settings, documented duplicate/conflicting declarations, and locations; valid but unimplemented features must not silently succeed. For VAR / ID / COPY / BY / FREQ / WEIGHT / Missing Values / Formatted versus Unformatted Values, construct valid, missing, empty, and multiple-group inputs; verify included observation counts, variable roles, BY boundaries, level ordering, and the frequency/weight rules relevant to this ticket; assert documented invalid-input behavior.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context; explicit statements: VAR, FREQ, WEIGHT |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: VAR, FREQ, WEIGHT. Remaining statement variants: ID, COPY, BY.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
