data ae;
  length usubjid $4 aeterm $10;
  input usubjid $ aeterm $ aesev seq;
  datalines;
S01 Headache 1 1
S01 Nausea 2 2
S02 Fatigue 1 1
;
run;
proc sort data=ae out=aeo(drop=seq rename=(aesev=severity)); by usubjid; run;
proc print data=aeo noobs; run;
