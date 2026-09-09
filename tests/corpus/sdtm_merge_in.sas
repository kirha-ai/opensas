/* Flag subjects who had any AE (MERGE with IN= + subsetting IF) */
data dm;
  input USUBJID $ SEX $;
  datalines;
01-001 M
01-002 F
01-003 M
;
run;
data ae;
  input USUBJID $ AETERM $;
  datalines;
01-001 HEADACHE
01-003 RASH
;
run;
proc sort data=dm; by USUBJID; run;
proc sort data=ae nodupkey; by USUBJID; run;
data flag;
  merge dm(in=ind) ae(in=ina);
  by USUBJID;
  if ind;
  hasae = ina;
  keep USUBJID SEX hasae;
run;
proc print data=flag; run;
