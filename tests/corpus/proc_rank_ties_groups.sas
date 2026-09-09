/* QA r24: PROC RANK uncovered surface — default (ties=mean), DESCENDING, GROUPS=.
   Ties share the average rank (2.5); GROUPS=4 = floor(rank*k/(n+1)). Verified
   against SAS 9.4 default TIES=MEAN. FRACTION fails loud (GAP-rankguards). */
data d; input x @@; datalines;
10 20 20 40 50 60 70 80
;
run;
proc rank data=d out=r;
  var x; ranks rx;
run;
proc print data=r noobs; run;

proc rank data=d out=rd descending;
  var x; ranks rxd;
run;
proc print data=rd noobs; run;

proc rank data=d out=g groups=4;
  var x; ranks grp;
run;
proc print data=g noobs; run;
