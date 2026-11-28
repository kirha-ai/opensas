/* STAT-FASTCLUS-001: PROC FASTCLUS missing values without NOMISS (p.2901)
 * and SHORT on invented data: an all-missing row is omitted and counted;
 * a partially missing row is clustered with the nvar/nonmissing-scaled
 * distance, never becomes a seed, and enters the per-variable statistics
 * only where present; a FREQ-variable value is ignored without a FREQ
 * statement. SHORT drops the seed, iteration-history, mean and standard
 * deviation tables. Expected listing: SAS 9.4 output of this same step; the
 * OUT= values were read from a SAS PROC PRINT of the same OUT= data set.
 * Blank lines between steps and at the end follow the opensas listing
 * convention (every other line and token is the SAS text).
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title;
data pts;
  input g $ id $ x y f;
  datalines;
A a1 1 1 1
A a2 2 1 2
A a3 1 2 1
A a4 8 8 1
A a5 9 8 1
A a6 8 9 3
A a7 . . 1
A a8 4 . 1
A a9 5 5 0
;
proc fastclus data=pts maxc=2 maxiter=5 out=o3 short;
  var x y;
run;
data _null_; set o3; file print; put id cluster distance 8.5; run;
