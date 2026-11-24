# STAT-GENMOD-019 — GENMOD — Displayed Output for Classical Analysis / Displayed Output for Bayesian Analysis / Displayed Output for Exact Analysis / ODS Table Names

## Source

S154 / Chapter 51 / `Displayed Output for Classical Analysis` (PDF pp. 3616–3624); S154 / Chapter 51 / `Displayed Output for Bayesian Analysis` (PDF pp. 3624–3626); S154 / Chapter 51 / `Displayed Output for Exact Analysis` (PDF pp. 3626–3627); S154 / Chapter 51 / `ODS Table Names` (PDF pp. 3627–3631).

## Scope

Implement Displayed Output for Classical Analysis; Displayed Output for Bayesian Analysis; Displayed Output for Exact Analysis; ODS Table Names. Cover all triggering options, content, and naming specified by this section; computational tickets supply numerical values, while other output types are handled separately.

## Acceptance criteria

For Displayed Output for Classical Analysis / Displayed Output for Bayesian Analysis / Displayed Output for Exact Analysis / ODS Table Names, verify table names, labels, triggering conditions, rows, columns, degrees of freedom, statistics, and missing representations; exercise selection and capture with ODS TRACE/OUTPUT; unrelated options must not create extra tables.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 51.11: Exact Poisson Regression |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
