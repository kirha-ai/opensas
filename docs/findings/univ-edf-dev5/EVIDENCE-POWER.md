# Actual SAS 9.4 M9 power EDF availability

Table 4.31 says power alpha<5 unknown has EDF tests. Actual M9 does not emit
those tests, even with fixed theta=0/sigma=1 and explicit ALPHA=EST. This was
verified separately from the probability-table extraction:

- Synthetic samples n=30 and 80 target shapes .2, 1 and 4.9.
- Default estimated-alpha requests and explicit ALPHA=EST both yield zero
  GoodnessOfFit rows. Actual fitted shapes are retained and are below 5:
  .20232801849515/ .20086889042838, 1.01164009247576/1.00434445214194,
  4.95703645313125/4.92128781549551.
- Specifying the corresponding known alpha yields six EDF rows per source
  request (D/W2/A2 for both sample sizes).
- Beta with alpha estimated and beta fixed at 1 likewise emits no EDF table.

The log explicitly notes that no EDF goodness-of-fit statistics are available
for the Power Function distribution. The final oracle has zero errors and
seven expected ODS warnings for the seven deliberately unavailable objects.
Source, output and log are retained. An earlier invalid SHAPE=EST alias probe
had syntax errors and was removed from this availability experiment; the
successful final source uses the documented ALPHA=EST spelling.

The helper now returns absent tests for estimated power, preserving the
fully-known table. This follows the task's actual M9 acceptance target, not
an implementation convenience or a simulation substitute. A unit regression
checks the observed fitted shapes and contrasts their specified counterparts.

Oracle command used unique `/tmp/opensas-dev5-edf-round2-20261113` paths with
`/Users/thomas/sas/bin/sasrun ... -f text`; final replay retained explicit
output/log files to establish the absence notes and warning/error counts.
