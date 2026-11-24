# STAT-MI-001 — MI — Data input, variable roles, and basic options

## Source

S154 / Chapter 82 / `PROC MI Statement` (PDF pp. 6425–6429); S154 / Chapter 82 / `BY Statement` (PDF p. 6429); S154 / Chapter 82 / `CLASS Statement` (PDF pp. 6429–6430); S154 / Chapter 82 / `FREQ Statement` (PDF p. 6436); S154 / Chapter 82 / `VAR Statement` (PDF pp. 6448–6449); S154 / Chapter 82 / `EM Algorithm for Data with Missing Values` (PDF pp. 6450–6451); S154 / Chapter 82 / `Missing Data Patterns` (PDF pp. 6452–6453); S154 / Chapter 82 / `Monotone Methods for Data Sets with Monotone Missing Patterns` (PDF pp. 6455–6456); S154 / Chapter 82 / `FCS Methods for Data Sets with Arbitrary Missing Patterns` (PDF pp. 6464–6466); S154 / Chapter 82 / `Input Data Sets` (PDF pp. 6476–6477).

## Scope

Integrate PROC MI declarations, basic options, defaults, and execution boundaries; this ticket establishes parameter objects and result interfaces, while later feature tickets implement model-, algorithm-, and output-specific options. Also implement BY; CLASS; FREQ; VAR; EM Algorithm for Data with Missing Values; Missing Data Patterns; Monotone Methods for Data Sets with Monotone Missing Patterns; FCS Methods for Data Sets with Arbitrary Missing Patterns; Input Data Sets; apply this procedure's rules for missing values, variable roles, and observation selection.

## Acceptance criteria

Create positive and negative parsing cases for the documented declarations and basic options; verify defaults, explicit settings, documented duplicate/conflicting declarations, and locations; valid but unimplemented features must not silently succeed. For BY / CLASS / FREQ / VAR / EM Algorithm for Data with Missing Values / Missing Data Patterns / Monotone Methods for Data Sets with Monotone Missing Patterns / FCS Methods for Data Sets with Arbitrary Missing Patterns / Input Data Sets, construct valid, missing, empty, and multiple-group inputs; verify included observation counts, variable roles, BY boundaries, level ordering, and the frequency/weight rules relevant to this ticket; assert documented invalid-input behavior.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Verified default procedure context; explicit statements: VAR |
| [statement_by.sas](statement_by.sas) | captured | 0 | [listing](statement_by.expected.txt) / [log](statement_by.oracle.log) | Two explicit BY groups contain identical inputs, exposing group boundaries and per-group results. |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: VAR. Remaining statement variants: BY, CLASS, FREQ.

**statement_by:** Targeted statement fixture adapted from the same chapter’s default data and the ticket’s statement syntax. Other statement options and edge cases remain future expansions.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
