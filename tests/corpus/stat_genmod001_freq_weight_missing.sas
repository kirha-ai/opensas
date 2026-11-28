/* STAT-GENMOD-001 close-out: PROC GENMOD observation selection and roles in
   the fitted Normal model (SAS/STAT 15.4 ch.51: FREQ p.3541, WEIGHT p.3567,
   Missing Values p.3616). Invented data. Every expected table below is the
   SAS 9.4 (SAS/STAT 15.4) listing of the same program (titles removed),
   captured 2026-11-28; none is regenerated from opensas.
   Verified rules: a dropped observation adds "Missing Values" (read - used);
   FREQ < 1 or missing and WEIGHT <= 0 or missing drop the observation; FREQ
   adds "Frequency Weight Variable" and the frequency sums (n = sum of FREQ);
   WEIGHT adds "Scale Weight Variable" and "Sum of Weights" and divides the
   dispersion by w; with both, an invalid-weight row is not in Sum of
   Frequencies Read; repeated MODEL: the last is used (WARNING) but variables
   of earlier MODEL statements still drop missing rows; repeated FREQ/WEIGHT:
   the first is used; a second DATA= is ignored (WARNING); STRATA without
   EXACT is ignored (WARNING); an empty input gives only a NOTE. */
options nocenter;
title;
data nor; input x y f w g; datalines;
0 5 1 1 1
0 7 2 0.5 1
0 9 1 2 1
1 7 3 1 1
1 10 1 1.5 1
1 8 1 1 1
2 11 2.7 1 1
2 9 1 3 1
3 16 1 1 2
3 13 1 1 2
3 14 0 1 2
4 25 1 -1 2
4 24 . 1 2
5 34 1 . 2
. 32 1 1 2
5 . 1 1 2
;
proc genmod data=nor; freq f; model y = x / dist=normal; run;
proc genmod data=nor; weight w; model y = x / dist=normal; run;
proc genmod data=nor; model y = x / dist=normal; run;
proc genmod data=nor; model y = x / dist=normal; model y = g / dist=normal; run;
proc genmod data=nor; freq f; freq w; model y = x / dist=normal; run;
proc genmod data=nor; weight f; weight w; model y = x / dist=normal; run;
data bym; set nor; if g=2 then y=.; run;
proc genmod data=nor data=bym; model y = x / dist=normal; run;
proc genmod data=nor; freq f; weight w; model y = x / dist=normal; run;
proc genmod data=nor; strata g; model y=x/dist=normal; run;
data empty; set nor; stop; run;
proc genmod data=empty; model y = x / dist=normal; run;
