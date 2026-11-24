# STAT-LIFEREG-012 — LIFEREG — OUTPUT / OUTEST= Data Set

## Source

S154 / Chapter 76 / `OUTPUT Statement` (PDF pp. 5559–5561); S154 / Chapter 76 / `OUTEST= Data Set` (PDF pp. 5581–5582).

## Scope

Implement OUTPUT; OUTEST= Data Set. Cover all triggering options, content, and naming specified by this section; computational tickets supply numerical values, while other output types are handled separately.

## Acceptance criteria

For OUTPUT / OUTEST= Data Set, verify triggering options, every variable name/type/format, row granularity, BY metadata, and numerical values; cover unrequested output, empty results, and multiple models; generate expected data sets independently of the implementation.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: LIFEREG Procedure; explicit statements: OUTPUT |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: OUTPUT. Remaining statement variants: . Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
