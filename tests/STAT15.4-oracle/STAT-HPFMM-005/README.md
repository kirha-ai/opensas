# STAT-HPFMM-005 — HPFMM — The Form of the Finite Mixture Model / Mixture Models Contrasted with Mixing and Mixed Models: Untangling the Terminology Web / Overdispersion

## Source

S154 / Chapter 58 / `The Form of the Finite Mixture Model` (PDF pp. 4570–4571); S154 / Chapter 58 / `Mixture Models Contrasted with Mixing and Mixed Models: Untangling the Terminology Web` (PDF pp. 4571–4572); S154 / Chapter 58 / `Overdispersion` (PDF pp. 4572–4573).

## Scope

Implement The Form of the Finite Mixture Model; Mixture Models Contrasted with Mixing and Mixed Models: Untangling the Terminology Web; Overdispersion. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For The Form of the Finite Mixture Model / Mixture Models Contrasted with Mixing and Mixed Models: Untangling the Terminology Web / Overdispersion, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Example 58.1: Modeling Mixing Probabilities: All Mice Are Equal, but Some Mice Are More Equal Than Others |

**documented_feature:** Draft functional example; the program is an observable reference for the stated case, not exhaustive coverage of this ticket. Fixed random seeds and explicitly bounded Bayesian iterations make this a reproducible, reduced-size fixture, not a convergence proof.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
