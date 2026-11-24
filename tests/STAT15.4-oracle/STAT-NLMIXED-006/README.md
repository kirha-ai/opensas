# STAT-NLMIXED-006 — NLMIXED — Built-In Log-Likelihood Functions / Compartment Models / Hierarchical Model Specification

S154 / Chapter 89 / `Built-In Log-Likelihood Functions` (PDF pp. 7131–7134); S154 / Chapter 89 / `Compartment Models` (PDF pp. 7134–7144); S154 / Chapter 89 / `Hierarchical Model Specification` (PDF pp. 7144–7146).

| Program | Expected output | Reference log | Status | Purpose |
|---|---|---|---:|---|
| [documented_feature.sas](documented_feature.sas) | [output](documented_feature.expected.txt) | [log](documented_feature.oracle.log) | 0 | Normal likelihood with nested cluster/person random effects and predictions. |

**documented_feature:** Explicit seeded synthetic hierarchy replaces the full COMET overdispersion example to bound regression runtime. Three-point quadrature is an intentionally small numerical fixture, not a high-accuracy integration study.
