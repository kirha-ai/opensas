# STAT-SURVEYPHREG-001 — SURVEYPHREG — Data input, variable roles, and basic options

## Source

S154 / Chapter 122 / `PROC SURVEYPHREG Statement` (PDF pp. 10010–10018); S154 / Chapter 122 / `BY Statement` (PDF pp. 10018–10019); S154 / Chapter 122 / `CLUSTER Statement` (PDF pp. 10021–10022); S154 / Chapter 122 / `FREQ Statement` (PDF pp. 10024–10025); S154 / Chapter 122 / `REPWEIGHTS Statement` (PDF pp. 10038–10040); S154 / Chapter 122 / `STRATA Statement` (PDF pp. 10040–10041); S154 / Chapter 122 / `WEIGHT Statement` (PDF pp. 10041–10042); S154 / Chapter 122 / `Missing Values` (PDF pp. 10054–10057).

## Scope

Integrate PROC SURVEYPHREG declarations, basic options, defaults, and execution boundaries; this ticket establishes parameter objects and result interfaces, while later feature tickets implement model-, algorithm-, and output-specific options. Also implement BY; CLUSTER; FREQ; REPWEIGHTS; STRATA; WEIGHT; Missing Values; apply this procedure's rules for missing values, variable roles, and observation selection.

## Acceptance criteria

Create positive and negative parsing cases for the documented declarations and basic options; verify defaults, explicit settings, documented duplicate/conflicting declarations, and locations; valid but unimplemented features must not silently succeed. For BY / CLUSTER / FREQ / REPWEIGHTS / STRATA / WEIGHT / Missing Values, construct valid, missing, empty, and multiple-group inputs; verify included observation counts, variable roles, BY boundaries, level ordering, and the frequency/weight rules relevant to this ticket; assert documented invalid-input behavior.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context; explicit statements: CLUSTER, STRATA, WEIGHT |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: CLUSTER, STRATA, WEIGHT. Remaining statement variants: BY, FREQ, REPWEIGHTS.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
