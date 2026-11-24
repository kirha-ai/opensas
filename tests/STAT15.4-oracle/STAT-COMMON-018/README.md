# STAT-COMMON-018 — Power and sample size inversion interface

## Source

S154 / Chapter 19 / `Computing Power and Sample Size` (PDF pp. 395–396); S154 / Chapter 19 / `Hypothesis Testing, Power, and Confidence Interval Precision` (PDF pp. 394–395).

## Scope

Implement shared solver contracts for power, sample size, and interval precision; procedure tickets specify distributions, rounding, solvable ranges, and design parameters for each test.

## Acceptance criteria

Cross-check forward power and inverse solutions; examine noninteger and executable sample sizes, unreachable targets, and endpoints; retain root-finding convergence status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [power_forward_inverse.sas](power_forward_inverse.sas) | captured | 0 | [listing](power_forward_inverse.expected.txt) / [log](power_forward_inverse.oracle.log) | Forward power versus sample size inversion and executable sample size rounding |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
