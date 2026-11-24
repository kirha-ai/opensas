# STAT-HPQUANTSELECT-011 — HPQUANTSELECT — OUTPUT / Output Data Set

## Source

S154 / Chapter 66 / `OUTPUT Statement` (PDF pp. 4991–4993); S154 / Chapter 66 / `Output Data Set` (PDF pp. 5007–5008).

## Scope

Implement OUTPUT; Output Data Set. Cover all triggering options, content, and naming specified by this section; computational tickets supply numerical values, while other output types are handled separately.

## Acceptance criteria

For OUTPUT / Output Data Set, verify triggering options, every variable name/type/format, row granularity, BY metadata, and numerical values; cover unrequested output, empty results, and multiple models; generate expected data sets independently of the implementation.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Seeded synthetic quantile-regression fixture: OUTPUT / Output Data Set |

**documented_feature:** Bounded adaptation of the documented syntax using 120 explicit seeded synthetic rows and three numeric covariates. It replaces the slow four-fit baseball illustration and preserves this ticket’s targeted behavior.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
