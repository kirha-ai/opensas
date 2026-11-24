# STAT-COMMON-014 — MCMC sampling and convergence diagnostic foundations

## Source

S154 / Chapter 8 / `Markov Chain Monte Carlo Method` (PDF pp. 157–164); S154 / Chapter 8 / `Assessing Markov Chain Convergence` (PDF pp. 164–177).

## Scope

Implement the chain state, warm-up, thinning, and convergence diagnostic interfaces introduced in the guide; implement procedure-specific samplers in separate tickets.

## Acceptance criteria

Fixed seeds must be reproducible; verify multiple-chain initial values, warm-up, and retained sample counts; use known distributions to check stationarity rather than comparing a single random result.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [normal_posterior.sas](normal_posterior.sas) | captured | 1 | [listing](normal_posterior.expected.txt) / [log](normal_posterior.oracle.log) | Normal posterior sampling, fixed seed, retained sample count and posterior/chain summaries |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
