options nodate nonumber;
data d;input g c x w f id $; datalines;
1 2 10 0 2 A
1 1 20 1 3 B
1 2 30 . 1 C
1 1 . 1 1 D
2 1 40 0 1 E
;
proc univariate data=d(where=(x ne 10)) idout freq modes nextrobs=3 nextrval=3;
by g; class c; var x; id id; freq f; weight w;
output out=o n=n nmiss=nm nobs=no mode=m pctlpts=0 50 100 pctlpre=p;
run;
proc print data=o; run;
data empty;set d(obs=0);run;
proc univariate data=empty noprint outtable=t;var x;output out=e n=n nmiss=nm nobs=no mean=m;run;
proc print data=e;run;proc contents data=e;run;
