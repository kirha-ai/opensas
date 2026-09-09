data raw; length subjid $4; input subjid $ v; datalines;
S002 3
S001 1
S001 2
S003 5
S002 4
;
run;
proc sort data=raw out=firstrec nodupkey; by subjid; run;
proc print data=firstrec noobs; run;
