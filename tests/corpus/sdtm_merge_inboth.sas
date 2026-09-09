/* Classify subjects as matched / DM-only / AE-only (MERGE with two IN= flags) */
data dm; input USUBJID $ SEX $; datalines;
01-001 M
01-002 F
01-003 M
;
run;
data ae; input USUBJID $ AETERM $; datalines;
01-002 RASH
01-003 NAUSEA
01-004 HEADACHE
;
run;
proc sort data=dm; by USUBJID; run;
proc sort data=ae nodupkey; by USUBJID; run;
data status;
  merge dm(in=ind) ae(in=ina);
  by USUBJID;
  length src $8;
  if ind and ina then src = "BOTH";
  else if ind then src = "DM";
  else src = "AE";
  keep USUBJID src;
run;
proc print data=status; run;
