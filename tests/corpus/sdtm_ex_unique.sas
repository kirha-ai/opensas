/* EX: one row per subject on treatment (PROC SORT NODUPKEY) */
data ex;
  input USUBJID $ EXTRT $ EXDOSE;
  datalines;
01-001 DRUG 50
01-001 DRUG 50
01-002 DRUG 100
01-002 DRUG 100
01-003 PLACEBO 0
;
run;

proc sort data=ex nodupkey out=subj;
  by USUBJID;
run;

proc print data=subj; run;
