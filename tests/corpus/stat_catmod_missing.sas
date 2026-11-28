/* STAT-CATMOD-001: PROC CATMOD input data sets and missing values.
 * 1) Raw data without WEIGHT: each observation is one subject ("Weight
 *    Variable None"); the listing was checked line-for-line against SAS.
 * 2) Frequency counts with missing values: observations with a missing
 *    MODEL variable are omitted and their weights reported as Frequency
 *    Missing (7 + 2 = 9); a missing or zero weight omits the observation
 *    and adds nothing (rule from a SAS run of the same shape). Expected
 *    values by hand: populations a (y=1: 4, y=2: 4) and b (2, 5);
 *    F = 1.5 and 12/7, V = 0.25/8 and (22/7 - 144/49)/7; intercept
 *    (F_a + F_b)/2 = 1.6071, g a = (F_a - F_b)/2 = -0.1071, both with
 *    variance (V_a + V_b)/4. Data: invented. */
options nodate nonumber nocenter linesize=160;
title;
data raw;
input g $ y @@;
datalines;
a 1 a 1 a 2 a 2 a 2 a 1 b 1 b 2 b 2 b 1 b 1 b 1 b 2
;
proc catmod data=raw;
response means;
model y=g;
run;
quit;
data mis;
input g $ y w @@;
datalines;
a 1 3 a 2 4 b 1 2 b 2 5 . 1 7 a . 2 b 1 . a 2 0 a 1 1
;
proc catmod data=mis;
weight w;
response means;
model y=g;
run;
quit;
/* NOPRINT prints nothing; NAMELEN=30 and ORDER=FORMATTED (no formats: the
   unformatted order) change nothing, so the listing equals the one above. */
proc catmod data=mis noprint; weight w; response means; model y=g; run; quit;
proc catmod data=mis namelen=30 order=formatted; weight w; response means; model y=g; run; quit;
