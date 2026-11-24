# STAT-MI-007 — MI — Monotone Propensity Score Method / Checking Convergence in FCS Methods / Combining Inferences from Multiply Imputed Data Sets

## Source

S154 / Chapter 82 / `Monotone Propensity Score Method` (PDF pp. 6463–6464); S154 / Chapter 82 / `Checking Convergence in FCS Methods` (PDF pp. 6466–6467); S154 / Chapter 82 / `Combining Inferences from Multiply Imputed Data Sets` (PDF pp. 6479–6481).

## Scope

Implement Monotone Propensity Score Method; Checking Convergence in FCS Methods; Combining Inferences from Multiply Imputed Data Sets. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Monotone Propensity Score Method / Checking Convergence in FCS Methods / Combining Inferences from Multiply Imputed Data Sets, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 82.11: Checking Convergence in MCMC |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
