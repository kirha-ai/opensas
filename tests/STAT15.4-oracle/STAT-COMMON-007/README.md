# STAT-COMMON-007 — Design matrices for main effects, interactions, and nesting

## Source

S154 / Chapter 20 / `GLM Parameterization of Classification Variables and Effects` (PDF pp. 414–418).

## Scope

Implement intercepts, continuous effects, categorical main effects, interactions, nesting, continuous/class combinations, and general effect expansion; retain the mapping from column names to model effects.

## Acceptance criteria

For small unbalanced designs, verify each design matrix column, its order, and its label; test empty cells, aliases, and no-intercept settings.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [effect_design.sas](effect_design.sas) | captured | 0 | [listing](effect_design.expected.txt) / [log](effect_design.oracle.log) | Main, interaction, continuous-by-class and intercept design columns |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
