# STAT-COMMON-016 — Complex survey design and variance interfaces

## Source

S154 / Chapter 15 / `Survey Design Specification` (PDF pp. 271–273); S154 / Chapter 15 / `Variance Estimation` (PDF pp. 273–274).

## Scope

Represent stratification, clustering, multistage designs, sampling weights, and population information consistently; support procedure integration with Taylor and replication variance methods.

## Acceptance criteria

Use enumerated small-population designs as references; verify stratum/PSU identifiers, finite population corrections, and replicate-weight dimensions; implement single-PSU handling according to the specific PROC.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [stratified_cluster_design.sas](stratified_cluster_design.sas) | captured | 0 | [listing](stratified_cluster_design.expected.txt) / [log](stratified_cluster_design.oracle.log) | Stratum and PSU identities, sampling weights and Taylor standard errors |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
