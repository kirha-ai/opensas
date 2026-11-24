# STAT-FREQ-003 — FREQ — TABLES

## Source

S154 / Chapter 47 / `TABLES Statement` (PDF pp. 3106–3154).

## Scope

Implement TABLES syntax, variable combinations, multidimensional tables/strata, frequencies and margins, level ordering, and missing/zero-frequency policies; the chapter's corresponding feature tickets own individual statistical tests, intervals, and graphics.

## Acceptance criteria

Verify one-way, multiway, nested, and combined-variable table specifications; check every cell count, margin, stratum, formatted-level order, and missing/zero-frequency behavior; corresponding statistical feature tickets validate tests and intervals.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: FREQ Procedure; explicit statements: TABLES |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: TABLES. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
