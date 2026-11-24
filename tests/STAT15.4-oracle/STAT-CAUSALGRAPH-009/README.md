# STAT-CAUSALGRAPH-009 — CAUSALGRAPH — Limitations of the CAUSALGRAPH Procedure

## Source

S154 / Chapter 37 / `Limitations of the CAUSALGRAPH Procedure` (PDF pp. 2329–2330).

## Scope

Implement Limitations of the CAUSALGRAPH Procedure. Cover the source suboptions, defaults, and applicability restrictions; implement only this feature group, without extending to languages or runtime environments outside the cited scope.

## Acceptance criteria

For Limitations of the CAUSALGRAPH Procedure, construct boundary or counterexamples for each explicit applicability restriction; verify diagnostics, termination status, and result availability; record specific needs-oracle questions for undocumented behavior rather than inventing successful behavior.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Getting Started: CAUSALGRAPH Procedure |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
