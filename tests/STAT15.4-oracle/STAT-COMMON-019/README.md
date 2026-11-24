# STAT-COMMON-019 — Clustering distances, transformations, and tie rules

## Source

S154 / Chapter 12 / `Introduction to Clustering Procedures` (PDF pp. 213–252); S154 / Chapter 10 / `Introduction to Multivariate Procedures` (PDF pp. 199–204); S154 / Chapter 11 / `Introduction to Discriminant Procedures` (PDF pp. 205–212).

## Scope

Provide sample/variable distance, standardization, and covariance/correlation input contracts for multivariate procedures; individual procedures implement their clustering, discrimination, or dimension-reduction algorithms.

## Acceptance criteria

Use manually calculated distance matrices to verify symmetry, scaling, and tie records; do not assume every proximity measure is Euclidean.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [distance_and_scaling.sas](distance_and_scaling.sas) | captured | 0 | [listing](distance_and_scaling.expected.txt) / [log](distance_and_scaling.oracle.log) | Distance symmetry, scaling and output matrix layout |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
