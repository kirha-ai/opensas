# STAT-NPAR1WAY-001 — NPAR1WAY — Data input, variable roles, and basic options

## Source

S154 / Chapter 90 / `PROC NPAR1WAY Statement` (PDF pp. 7215–7224); S154 / Chapter 90 / `BY Statement` (PDF p. 7224); S154 / Chapter 90 / `CLASS Statement` (PDF pp. 7224–7225); S154 / Chapter 90 / `FREQ Statement` (PDF pp. 7229–7230); S154 / Chapter 90 / `STRATA Statement` (PDF pp. 7233–7235); S154 / Chapter 90 / `VAR Statement` (PDF p. 7235); S154 / Chapter 90 / `Missing Values` (PDF pp. 7235–7236).

## Scope

Integrate PROC NPAR1WAY declarations, basic options, defaults, and execution boundaries; this ticket establishes parameter objects and result interfaces, while later feature tickets implement model-, algorithm-, and output-specific options. Also implement BY; CLASS; FREQ; STRATA; VAR; Missing Values; apply this procedure's rules for missing values, variable roles, and observation selection.

## Acceptance criteria

Create positive and negative parsing cases for the documented declarations and basic options; verify defaults, explicit settings, documented duplicate/conflicting declarations, and locations; valid but unimplemented features must not silently succeed. For BY / CLASS / FREQ / STRATA / VAR / Missing Values, construct valid, missing, empty, and multiple-group inputs; verify included observation counts, variable roles, BY boundaries, level ordering, and the frequency/weight rules relevant to this ticket; assert documented invalid-input behavior.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context; explicit statements: CLASS, VAR |
| [statement_by.sas](statement_by.sas) | captured | 0 | [listing](statement_by.expected.txt) / [log](statement_by.oracle.log) | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: CLASS, VAR. Remaining statement variants: BY, FREQ, STRATA.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
