data vs; length subjid $4 visit $4; input subjid $ visit $ sbp; datalines;
S002 V1 130
S001 V2 125
S001 V1 128
S002 V2 135
S001 V1 122
;
run;
proc sort data=vs out=srt; by subjid visit descending sbp; run;
proc print data=srt noobs; run;
