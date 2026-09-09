/* BUG-meansidnoop: PROC MEANS ID statement — each id var rides into OUTPUT as
   its within-group MAX (SAS semantics), at every _TYPE_ level; previously the
   statement had no parse branch and was silently discarded.
   (a) CLASS: id max per class level AND for the _TYPE_=0 overall row.
   (b) BY + NWAY: id vars (num and char) after the BY column, before the stats.
   (c) A numeric missing id never wins the max.
   Hand-verified vs SAS 9.4 (Base Procedures Guide, MEANS ID statement). */
data d; input id g $ x; datalines;
1 A 10
2 A 20
3 B 30
4 B 40
;
run;
/* (a) overall row id=4 (max over all), A→2, B→4 */
proc means data=d noprint; class g; id id; var x; output out=oa mean=m n=cnt; run;
proc print data=oa noobs; run;
/* (b) BY+NWAY: char id maxes blank-padded ASCII (B2 > B10), num y max too */
data h; input g $ iid $ y x; datalines;
A B10 5 1
A B2  9 2
B C1  7 3
;
run;
proc means data=h noprint nway; by g; id iid y; var x; output out=ob mean=m; run;
proc print data=ob noobs; run;
/* (c) missing id (.) loses to any present value; group of all-missing → . */
data m; input id x; datalines;
. 1
2 2
. 3
;
run;
proc means data=m noprint; id id; var x; output out=oc mean=m; run;
proc print data=oc noobs; run;
