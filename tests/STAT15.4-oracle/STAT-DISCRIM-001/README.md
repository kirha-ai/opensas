# STAT-DISCRIM-001 — DISCRIM — Data input, variable roles, and basic options

## Source

S154 / Chapter 42 / `PROC DISCRIM Statement` (PDF pp. 2652–2660); S154 / Chapter 42 / `BY Statement` (PDF pp. 2660–2661); S154 / Chapter 42 / `CLASS Statement` (PDF p. 2661); S154 / Chapter 42 / `FREQ Statement` (PDF pp. 2661–2662); S154 / Chapter 42 / `ID Statement` (PDF p. 2662); S154 / Chapter 42 / `VAR Statement` (PDF pp. 2663–2664); S154 / Chapter 42 / `WEIGHT Statement` (PDF p. 2664); S154 / Chapter 42 / `Missing Values` (PDF p. 2664); S154 / Chapter 42 / `Input Data Sets` (PDF pp. 2675–2676).

## Scope

Integrate PROC DISCRIM declarations, basic options, defaults, and execution boundaries; this ticket establishes parameter objects and result interfaces, while later feature tickets implement model-, algorithm-, and output-specific options. Also implement BY; CLASS; FREQ; ID; VAR; WEIGHT; Missing Values; Input Data Sets; apply this procedure's rules for missing values, variable roles, and observation selection.

## Acceptance criteria

Create positive and negative parsing cases for the documented declarations and basic options; verify defaults, explicit settings, documented duplicate/conflicting declarations, and locations; valid but unimplemented features must not silently succeed. For BY / CLASS / FREQ / ID / VAR / WEIGHT / Missing Values / Input Data Sets, construct valid, missing, empty, and multiple-group inputs; verify included observation counts, variable roles, BY boundaries, level ordering, and the frequency/weight rules relevant to this ticket; assert documented invalid-input behavior.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 1 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context; explicit statements: CLASS |
| [statement_by.sas](statement_by.sas) | captured | 1 | [listing](statement_by.expected.txt) / [log](statement_by.oracle.log) | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: CLASS. Remaining statement variants: BY, FREQ, ID, VAR, WEIGHT.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
