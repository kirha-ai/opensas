/* STAT-GENMOD-001 close-out: a BY group without valid observations.
   expect-rc: 1
   SAS 9.4 (SAS/STAT 15.4), captured 2026-11-28: group g=1 is fitted and
   printed; group g=2 (every response missing) prints nothing and the log gets
   "ERROR: No valid observations due to invalid or missing values in the
   response, explanatory, offset, frequency, or weight variable." followed by
   the BY-group NOTE. The expected listing is the SAS listing (title removed).
   Known whitespace-only difference: opensas centers the BY line even under
   NOCENTER (shared BY-line helper); SAS prints it flush left. Invented data. */
options nocenter;
title;
data bym; input x y g; datalines;
0 5 1
0 7 1
0 9 1
1 7 1
1 10 1
1 8 1
2 11 1
2 9 1
3 . 2
3 . 2
4 . 2
;
proc genmod data=bym; by g; model y = x / dist=normal; run;
