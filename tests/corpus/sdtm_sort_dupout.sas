/* NODUPKEY with DUPOUT= captures the dropped duplicate-key rows */
data q; input USUBJID $ SEQ; datalines;
01-001 1
01-001 2
01-002 1
01-003 1
01-003 2
;
run;
proc sort data=q nodupkey out=firsts dupout=dups;
  by USUBJID;
run;
data _null_; set firsts; put "keep " USUBJID= SEQ=; run;
data _null_; set dups; put "dup  " USUBJID= SEQ=; run;
