data qs; length subjid $4 item $4; input subjid $ item $ score; datalines;
S001 Q1 5
S001 Q1 5
S001 Q2 3
S002 Q1 4
S002 Q1 9
;
run;
proc sort data=qs out=firstscore nodupkey; by subjid item; run;
proc print data=firstscore noobs; run;
