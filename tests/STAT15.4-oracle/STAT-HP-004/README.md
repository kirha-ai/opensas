# STAT-HP-004 — HP model selection methods and SELECTION

## Source

S154 / Chapter 22 / `SELECTION Statement` (PDF pp. 564–570); S154 / Chapter 22 / `Model Selection` (PDF pp. 570–577).

## Scope

Implement shared model selection statements and selection, stopping, and final-choice criteria; integrate procedure-specific methods and restrictions separately.

## Acceptance criteria

On small models that can be exhaustively checked, verify stepwise paths, ties, stopping reasons, and the final model; distinguish entry criteria from final-choice criteria.

## Cases

| Program | Status | SAS status | Expected listing | Discriminates |
|---|---|---:|---|---|
| [native_contract.sas](native_contract.sas) | captured | 0 | [listing](native_contract.expected.txt) / [log](native_contract.oracle.log) | HP CLASS/variable role integration, single-thread PERFORMANCE information and stepwise selection |

**native_contract:** Draft case captures the stated observable contract; it is not exhaustive coverage of the ticket.

A captured case is an observed SAS reference, not a claim that every option in this ticket is covered. Read each case’s stated discriminating behavior and coverage notes.
