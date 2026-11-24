# SAS/STAT 15.4 test cases

1,422 ticket directories contain 1,542 cases linked from [stat-jira.md](../../stat-jira.md).

Each case contains:

- `.sas`: input data and SAS program.
- `.expected.txt`: expected text output.
- `.oracle.log`: reference log.
- `.expected.rc`: reference status (`0` clean, `1` warning, `2` error).
- `.expected.diagnostics.txt`: expected warnings or errors, when applicable.

Each ticket README lists its cases, PDF pages, and coverage notes. See [inputs.md](inputs.md) for SASHELP data dependencies and [coverage.md](coverage.md) for remaining coverage gaps. Text output alone does not verify graphics.
