/* NODUPREC removes fully-identical rows (all variables equal) */
data ae; input USUBJID $ AETERM $ AESEV $; datalines;
01-001 HEADACHE MILD
01-001 HEADACHE MILD
01-001 NAUSEA MODERATE
01-002 RASH MILD
;
run;
proc sort data=ae noduprec out=dedup;
  by USUBJID;
run;
proc print data=dedup; run;
