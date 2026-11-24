# STAT-GLIMMIX-018 — GLIMMIX — The Likelihood Ratio Test / Wald Versus Likelihood Ratio Tests / Confidence Bounds Based on Likelihoods / One- and Two-Sided Testing, Mixture Distributions / Handling the Degenerate Distribution

## Source

S154 / Chapter 52 / `The Likelihood Ratio Test` (PDF pp. 3848–3849); S154 / Chapter 52 / `Wald Versus Likelihood Ratio Tests` (PDF p. 3851); S154 / Chapter 52 / `Confidence Bounds Based on Likelihoods` (PDF pp. 3851–3855); S154 / Chapter 52 / `One- and Two-Sided Testing, Mixture Distributions` (PDF pp. 3849–3851); S154 / Chapter 52 / `Handling the Degenerate Distribution` (PDF p. 3851).

## Scope

Implement The Likelihood Ratio Test; Wald Versus Likelihood Ratio Tests; Confidence Bounds Based on Likelihoods; One- and Two-Sided Testing, Mixture Distributions; Handling the Degenerate Distribution. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For The Likelihood Ratio Test / Wald Versus Likelihood Ratio Tests / Confidence Bounds Based on Likelihoods / One- and Two-Sided Testing, Mixture Distributions / Handling the Degenerate Distribution, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 52.4: Quasi-likelihood Estimation for Proportions with Unknown Distribution |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
