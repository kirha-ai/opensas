/* Two-way frequency: treatment arm by sex (PROC FREQ tables A*B) */
data dm;
  input USUBJID $ ARM $ SEX $;
  datalines;
01-001 DRUG M
01-002 DRUG F
01-003 PLACEBO M
01-004 DRUG M
01-005 PLACEBO F
01-006 PLACEBO M
;
run;

proc freq data=dm;
  tables ARM*SEX;
run;
