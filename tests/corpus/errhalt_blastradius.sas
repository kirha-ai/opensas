/* SEV-errhaltblastradius — PIN, not a fix. A step that takes one of the rc
   epic's 2 -> 1 user-error conditions (here: numeric format 8.2 applied to a
   character variable, ERROR rc 1) records a step error, which puts the run
   into syntax-check mode (BUG-errhalt), so EVERY later step is SKIPPED:
   stdout is EMPTY even though the clean `data b` / `proc print data=b` pair
   would print a table on its own. This is CORRECT — the `proc means by x`
   unsorted twin suppressed later output the same way before the epic
   (verified by probe), so the slice removed an inconsistency, it did not
   create one. No corpus program put a step after such a condition until now.
   A REGRESSION looks like: stdout gains the `b` table (later steps run
   again — the inconsistency restored) or the rc moves off 1. The matching
   control fixture errhalt_blastradius_control pins the other direction:
   clean steps MUST still run and print. expect-rc: 1 */
data a; c='ab'; n=1; run;
proc print data=a; format c 8.2; run;
data b; set a; m = n + 1; run;
proc print data=b; run;
