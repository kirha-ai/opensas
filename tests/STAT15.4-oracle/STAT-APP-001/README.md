# STAT-APP-001 — Power and Sample Size Application product scope and launch contract

## Source

S154 / Chapter 97 / `The Power and Sample Size Application` (PDF pp. 7989–7990).

## Scope

Document this application's launch mechanism, supported environments, and relationship to POWER/GLMPOWER; itemize GUI or external-runtime requirements not specified here, then define an implementable UI/integration scope.

## Acceptance criteria

Deliver a source-backed capability boundary and executable entry-point design; identify behavior this guide does not specify; additional GUI work needs supplementary specifications before claiming full compatibility.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [native_contract.sas](native_contract.sas) | captured | 0 | [listing](native_contract.expected.txt) / [log](native_contract.oracle.log) | Installed SAS/STAT product availability and the POWER computation behind the application |

**native_contract:** Draft case captures the stated observable contract; it is not exhaustive coverage of the ticket. The desktop application UI and launch environment are outside this CLI case and remain a separate specification/verification concern.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
