/* STAT-HPREG-001: PROC HPREG BY, FREQ and WEIGHT rules: two BY groups;
 * FREQ values truncated, below 1 or missing exclude the observation;
 * nonpositive or missing WEIGHT excludes it; Sum of Frequencies lines;
 * FREQ alone, WEIGHT alone, CLASS with FREQ and WEIGHT, and a parameter
 * column widened by long effect and CLASS level names.
 * Expected listing: SAS 9.4 (SAS/STAT 15.4) output of this program.
 * Invented data.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
data work.inv2;
  input b y x1 x2 g $ f w;
  datalines;
1 3.1 1 4 A 1 1.0
1 5.0 2 3 B 2 2.0
1 4.2 3 5 A 1 0.5
1 6.9 4 2 B 3 1.5
1 6.4 5 6 A 0 1.0
1 8.8 6 1 B 2.7 2.5
1 8.6 7 7 A 1 0
1 7.1 8 3 B 1 .
1 9.9 9 5 A . 1.0
1 . 8 3 B 1 1.0
2 2.2 1 2 A 1 1.0
2 4.9 2 6 B 1 3.0
2 3.1 3 1 A 2 1.0
2 7.3 4 5 B 1 0.5
2 5.8 5 3 A 1 1.0
2 9.5 6 8 B 2 2.0
2 8.1 7 4 A 1 1.0
2 9.0 8 2 B 1 1.5
;
proc hpreg data=inv2;
  by b;
  freq f;
  weight w;
  model y = x1 x2;
run;
proc hpreg data=inv2;
  freq f;
  model y = x1 x2;
run;
proc hpreg data=inv2;
  weight w;
  model y = x1 x2;
run;
proc hpreg data=inv2;
  class g;
  freq f;
  weight w;
  model y = x1 g x2;
run;
data work.longnm;
  set inv2;
  length category $8;
  longername1 = x1;
  category = ifc(g='A', 'alpha', 'beta');
run;
proc hpreg data=longnm;
  class category;
  model y = longername1 category;
run;
