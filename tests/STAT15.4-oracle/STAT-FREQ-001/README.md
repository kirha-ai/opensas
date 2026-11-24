# STAT-FREQ-001 — FREQ — Data input, variable roles, and basic options

## Source

S154 / Chapter 47 / `PROC FREQ Statement` (PDF pp. 3082–3084); S154 / Chapter 47 / `BY Statement` (PDF pp. 3084–3085); S154 / Chapter 47 / `WEIGHT Statement` (PDF pp. 3157–3158); S154 / Chapter 47 / `Inputting Frequency Counts` (PDF pp. 3158–3159); S154 / Chapter 47 / `Grouping with Formats` (PDF pp. 3159–3160); S154 / Chapter 47 / `Missing Values` (PDF pp. 3160–3162).

## Scope

Integrate PROC FREQ declarations, basic options, defaults, and execution boundaries; this ticket establishes parameter objects and result interfaces, while later feature tickets implement model-, algorithm-, and output-specific options. Also implement BY; WEIGHT; Inputting Frequency Counts; Grouping with Formats; Missing Values; apply this procedure's rules for missing values, variable roles, and observation selection.

## Acceptance criteria

Create positive and negative parsing cases for the documented declarations and basic options; verify defaults, explicit settings, documented duplicate/conflicting declarations, and locations; valid but unimplemented features must not silently succeed. For BY / WEIGHT / Inputting Frequency Counts / Grouping with Formats / Missing Values, construct valid, missing, empty, and multiple-group inputs; verify included observation counts, variable roles, BY boundaries, level ordering, and the frequency/weight rules relevant to this ticket; assert documented invalid-input behavior.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context; explicit statements: WEIGHT |
| [statement_by.sas](statement_by.sas) | captured | 0 | [listing](statement_by.expected.txt) / [log](statement_by.oracle.log) | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: WEIGHT. Remaining statement variants: BY.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
