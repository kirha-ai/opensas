# STAT-FREQ-004 — FREQ — EXACT / Exact Statistics

## Source

S154 / Chapter 47 / `EXACT Statement` (PDF pp. 3085–3094); S154 / Chapter 47 / `Exact Statistics` (PDF pp. 3234–3238).

## Scope

Implement EXACT; Exact Statistics. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For EXACT / Exact Statistics, independently enumerate probability masses and the relevant tails/intervals for small samples; cover ties, zero counts, degenerate boundaries, and exact-method applicability restrictions.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 47.5: Analysis of a 2x2 Contingency Table; explicit statements: EXACT |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: EXACT. Remaining statement variants: . Restored the preceding official FORMAT definitions from physical PDF page 3269.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
