# STAT-NLMIXED-006 — NLMIXED — Built-In Log-Likelihood Functions / Compartment Models / Hierarchical Model Specification

## Source

S154 / Chapter 89 / `Built-In Log-Likelihood Functions` (PDF pp. 7131–7134); S154 / Chapter 89 / `Compartment Models` (PDF pp. 7134–7144); S154 / Chapter 89 / `Hierarchical Model Specification` (PDF pp. 7144–7146).

## Scope

Implement Built-In Log-Likelihood Functions; Compartment Models; Hierarchical Model Specification. This ticket owns the feature's options, defaults, computation, and results as an extension of the basic computational path; the chapter's output tickets handle ODS descriptors and file presentation.

## Acceptance criteria

For Built-In Log-Likelihood Functions / Compartment Models / Hierarchical Model Specification, use an independently calculable small sample and the source examples to verify targets, estimates/statistics, degrees of freedom, and applicable probabilities or intervals; include at least one relevant degenerate or boundary case, asserting documented diagnostics and result status.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [documented_feature.sas](documented_feature.sas) | captured | 0 | [listing](documented_feature.expected.txt) / [log](documented_feature.oracle.log) | Normal likelihood with nested cluster/person random effects and predictions. |

**documented_feature:** Explicit seeded synthetic hierarchy replaces the full COMET overdispersion example to bound regression runtime. Three-point quadrature is an intentionally small numerical fixture, not a high-accuracy integration study.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
