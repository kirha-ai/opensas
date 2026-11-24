# STAT-HPFMM-010 — HPFMM — OUTPUT / Output Data Set

## Source

S154 / Chapter 58 / `OUTPUT Statement` (PDF pp. 4563–4565); S154 / Chapter 58 / `Output Data Set` (PDF pp. 4588–4589).

## Scope

Implement OUTPUT; Output Data Set. Cover all triggering options, content, and naming specified by this section; computational tickets supply numerical values, while other output types are handled separately.

## Acceptance criteria

For OUTPUT / Output Data Set, verify triggering options, every variable name/type/format, row granularity, BY metadata, and numerical values; cover unrequested output, empty results, and multiple models; generate expected data sets independently of the implementation.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: HPFMM Procedure; explicit statements: OUTPUT |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: OUTPUT. Remaining statement variants: . Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
