/* Sequence number within each subject (counter reset on FIRST.) */
data ae; input USUBJID $ AETERM $; datalines;
01-001 HEADACHE
01-001 NAUSEA
01-001 RASH
01-002 FATIGUE
01-002 FEVER
;
run;
proc sort data=ae; by USUBJID; run;
data seq;
  set ae;
  by USUBJID;
  if first.USUBJID then aeseq = 0;
  aeseq + 1;
run;
proc print data=seq; var USUBJID AETERM aeseq; run;
