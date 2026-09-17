/* GH#8 ISS-sortmissingerr: PROC SORT on a MISSING member is a hard ERROR in
   SAS 9.4 (confirmed on SAS Studio: "ERROR: File WORK.NOPE.DATA does not
   exist." + "NOTE: The SAS System stopped processing this step because of
   errors.") — the user named a table that is not there, a USER error (D-009),
   rc 1. The old warn+skip at rc 0 (SORT-emptytol's absent half) let a pipeline
   run on an absent input; the DATA-step SET has hard-errored the identical
   shape since BUG-setmissingquiet, so SORT now matches it (D-009b: same
   condition, same text, same rc). The ERROR + NOTE go to stderr (pinned by
   the captured-diagnostics test in src/proc.zig); stdout pins the BATCH
   consequence (BUG-errhalt syntax-check mode): "before" runs, the SORT step
   dies, and every later step is skipped — "pipeline survived" no longer
   survives a missing member. This replaces the pin sort_emptytol used to
   carry.
   expect-rc: 1 */
data _null_; put "before"; run;
proc sort data=ghost out=g1; by g; run;
data _null_; put "pipeline survived"; run;
