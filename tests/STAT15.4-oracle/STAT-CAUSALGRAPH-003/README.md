# STAT-CAUSALGRAPH-003 — CAUSALGRAPH — MODEL / UNMEASURED / Arrow or Edge Specification

## Source

S154 / Chapter 37 / `MODEL Statement` (PDF pp. 2316–2319); S154 / Chapter 37 / `UNMEASURED Statement` (PDF p. 2321); S154 / Chapter 37 / `Arrow or Edge Specification` (PDF pp. 2328–2329).

## Scope

Implement MODEL; UNMEASURED; Arrow or Edge Specification. Implement the syntax and model semantics allowed by this procedure, using shared effect/parameterization support only for forms documented as supported.

## Acceptance criteria

For MODEL / UNMEASURED / Arrow or Edge Specification, verify nodes, connections, unmeasured variables, and graph validity for documented graph/edge types; enumerate or manually derive identification conditions for small graphs; explicitly report invalid or nonidentified structures.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: CAUSALGRAPH Procedure; explicit statements: MODEL, UNMEASURED |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Statement-token coverage: MODEL, UNMEASURED. Remaining statement variants: .

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
