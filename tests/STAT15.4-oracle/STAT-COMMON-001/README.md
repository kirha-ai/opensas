# STAT-COMMON-001 — Statistical procedure execution and the 15.4 option contract

## Source

S154 / Chapter 3 / `Introduction` (PDF pp. 27–36); S154 / Chapter 2 / `What's New in SAS/STAT 15.4` (PDF pp. 25–26); S154 / Chapter 1 / `Procedures by Category` (PDF pp. 13–24).

## Scope

Establish PROC-level parsing, default-parameter, execution-status, and result-object contracts; distinguish valid input, invalid input, and unsupported capabilities under SAS/STAT 15.4. This ticket owns shared interfaces; PROC tickets own their semantics.

## Acceptance criteria

Provide minimal execution contract tests; define option defaults, explicit overrides, and procedure-specific RUN/QUIT rules; emit locatable diagnostics for unimplemented branches; record the specification version and handle version differences explicitly.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [runtime_contract.sas](runtime_contract.sas) | captured | 0 | [listing](runtime_contract.expected.txt) / [log](runtime_contract.oracle.log) | Runtime version, PROC dispatch, RUN/QUIT and default result objects |

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
