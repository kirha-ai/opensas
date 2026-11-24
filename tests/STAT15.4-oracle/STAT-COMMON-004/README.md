# STAT-COMMON-004 — Linear model moments and covariance foundations

## Source

S154 / Chapter 4 / `Expectations of Random Variables and Vectors` (PDF pp. 65–68); S154 / Chapter 4 / `Mean Squared Error` (PDF pp. 68–69); S154 / Chapter 4 / `Linear Model Theory` (PDF pp. 69–80); S154 / Chapter 7 / `Introduction to Mixed Modeling Procedures` (PDF pp. 135–148).

## Scope

Implement shared linear model moments, residual sums of squares, variance, and covariance calculations; preserve the distinction between frequency and analysis weights.

## Acceptance criteria

Use manually calculable intercept-only, weighted, and rank-deficient models to verify coefficients, residuals, degrees of freedom, and covariance; verify scaling relationships.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [weighted_linear_moments.sas](weighted_linear_moments.sas) | captured | 0 | [listing](weighted_linear_moments.expected.txt) / [log](weighted_linear_moments.oracle.log) | Weighted normal equations, residual variance and coefficient covariance |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
