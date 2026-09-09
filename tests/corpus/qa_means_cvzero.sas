/* qa_means_cvzero: PROC MEANS CV = 100*Std/Mean is undefined when the mean is
   exactly 0 (e.g. change-from-baseline that cancels). SAS 9.4 emits a MISSING
   value for CV rather than a divide-by-zero error or 0. A group with a nonzero
   mean gets a finite CV, so both branches are exercised in one nway run. */
data cfb;
  input subj grp chg @@;
  datalines;
1 1 -4  2 1 4  3 1 -2  4 1 2
5 2 10  6 2 20  7 2 30
;
run;

proc means data=cfb nway mean std cv;
  class grp;
  var chg;
run;

proc means data=cfb nway noprint;
  class grp;
  var chg;
  output out=o mean=mean std=std cv=cv;
run;
proc print data=o noobs; run;
