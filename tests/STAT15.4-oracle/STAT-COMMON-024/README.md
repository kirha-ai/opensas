# STAT-COMMON-024 — EFFECTPLOT Statement

## Source

S154 / Chapter 20 / `EFFECTPLOT Statement` (PDF pp. 444–472).

## Scope

Implement shared semantics, defaults, and applicability checks for EFFECTPLOT Statement; procedure-specific options and result integration belong to the corresponding PROC tickets.

## Acceptance criteria

Create positive and negative cases for the syntax forms, defaults, and option combinations listed in this section; verify result names, dimensions, and numerical values.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [effectplot_fit.sas](effectplot_fit.sas) | captured | 0 | [listing](effectplot_fit.expected.txt) / [log](effectplot_fit.oracle.log) | EFFECTPLOT fit request and ODS graph identity |

**effectplot_fit:** Visual artifacts are not represented by the text listing alone.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
