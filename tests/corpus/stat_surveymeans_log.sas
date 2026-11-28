/* STAT-SURVEYMEANS-001: log diagnostics of observation selection and
 * repeated declarations. Invented data. Expected log lines are the SAS 9.4
 * (SAS/STAT 15.4) log of the same steps (reference run 2026-11-28): the
 * repeated WEIGHT WARNING, the nonpositive-weight NOTE, the single-unit
 * stratum NOTEs (cluster / observation wording) and "No observations." with
 * no listing when every weight is nonpositive.
 */
options nodate nonumber nocenter linesize=160;
data a;
input y z w s c;
datalines;
11 4 2 1 1
13 5 0 1 1
12 . 1 1 2
16 7 3 2 3
. 2 . 2 3
14 3 1 2 4
-9 1 1 . 4
15 6 2 2 5
;
proc surveymeans data=a; var z; weight w; weight s; run;
proc surveymeans data=a; var y z; strata s; cluster c; run;
proc surveymeans data=a; var z; strata s c; run;
data h; input y w; datalines;
1 0
2 .
;
proc surveymeans data=h; var y; weight w; run;
data b;
input y z s c;
datalines;
11 4 1 1
13 5 1 1
16 7 2 3
14 3 2 4
15 6 2 5
;
proc surveymeans data=b; var y z; strata s c; run;
