data labs; length subjid $4; input subjid $ val; datalines;
S001 3.2
S002 1.1
S001 8.5
S003 4.4
S002 9.9
;
run;
proc sort data=labs out=hi; by descending val; run;
proc print data=hi noobs; run;
