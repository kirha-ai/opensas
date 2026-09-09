data d; input subj val; datalines;
1 10
1 30
2 20
;
run;
proc transpose data=d out=w; by subj; var val; run;
proc print data=w; run;
