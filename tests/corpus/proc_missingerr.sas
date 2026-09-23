/* BUG-procmissingrc2: a MISSING input table is a USER error (D-009 rc 1),
   not an opensas gap (rc 2). MEANS/REPORT/TABULATE now take the same
   absent-input arm the DATA-step SET has had since BUG-setmissingquiet and
   PROC SORT since GH#8: real SAS 9.4 errors "ERROR: File WORK.NOPE.DATA does
   not exist." and ends the failing step with "NOTE: The SAS System stopped
   processing this step because of errors." (both on STDERR, pinned by the
   captured-diagnostics test in src/proc.zig — never a real aborting run).
   stdout pins the batch consequence (BUG-errhalt syntax-check mode): "before"
   runs, the MEANS step dies on the absent table, every later step — the
   REPORT sibling included — is skipped, and the "pipeline survived" canary
   must NOT appear. Before this fix the missing table filed a rc-2
   "UNSUPPORTED: PROC MEANS: no input dataset" gap: the PROC is supported,
   the user's table just is not there.
   expect-rc: 1 */
data _null_; put "before"; run;
proc means data=nope; run;
proc report data=nope; run;
data _null_; put "pipeline survived"; run;
