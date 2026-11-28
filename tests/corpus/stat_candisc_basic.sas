/* expect-rc: 1
 * STAT-CANDISC-001: default PROC CANDISC listing (Counts, NObs, Levels,
 * MultStat, CanCorr, TStruc/BStruc/PStruc, TCoef/PCoef/RCoef, CanonicalMeans)
 * and OUT= scores. One observation has a missing VAR value and one a missing
 * CLASS value (Missing Values, PDF p.2161): both are excluded from the fit
 * with the three SAS warnings (rc 1); the missing-CLASS observation still
 * gets scores, and without NCAN= OUT= carries v=3 score variables of which
 * the last v-(c-1) are missing (NCAN=, p.2157). Invented data; expected
 * listing is the SAS 9.4 output of this program, minus the blank line SAS
 * writes at the top of each page (opensas page convention).
 */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
title 'Invented Plants';
data plants;
  input grp $ x1 x2 x3 f w;
  if grp = "." then grp = " ";
  datalines;
A 2.1 3.5 1.0 1 1.0
A 2.5 3.1 1.4 2 0.5
A 1.9 3.9 0.8 1 1.5
A 2.8 3.3 1.9 1 1.0
A 2.2 . 1.1 1 1.0
B 3.9 2.2 2.5 1 2.0
B 4.4 2.0 2.9 3 1.0
B 3.6 2.9 2.1 1 1.0
B 4.1 2.4 3.3 1 0.5
C 5.2 4.1 1.2 2 1.0
C 5.9 4.6 0.7 1 1.0
C 6.3 3.8 1.6 1 1.5
C 5.5 4.9 1.1 1 1.0
. 4.0 3.0 2.0 1 1.0
;
proc candisc data=plants out=sc;
  class grp;
  var x1 x2 x3;
run;
title;
data _null_;
  set sc;
  file print;
  c3_missing = missing(Can3);
  if missing(Can1) then put grp $1. ' no scores ' c3_missing=;
  else put grp $1. +1 Can1 9.5 +1 Can2 9.5 ' ' c3_missing=;
run;
