/* GH#71 ISS-dkricond: an INPUT-side drop= of a never-referenced var is FATAL in
   SAS 9.4 (DKRICOND=ERROR) — unlike the DROP/KEEP *statement*, which is a
   DKROCOND=WARN case (see keep_nonexist_warn). The step aborts with 0 obs and
   poisons downstream (syntax-check mode), so the final PUT never runs. Contrast
   keep_nonexist_warn, where the trailing step DOES print. Expected stdout is
   empty; any line here means the fatal abort regressed back to a warning.
   expect-rc: 1 */
data a;
  x = 1;
run;

data b;
  set a (drop=NOTHERE);   /* NOTHERE never referenced -> ERROR, step aborts, b=0 obs */
run;

data _null_;
  set b;
  put "REGRESSED: input drop of nonexistent var did not abort; x=" x;
run;
