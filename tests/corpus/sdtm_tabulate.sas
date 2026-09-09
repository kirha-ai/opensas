/* Subject counts by arm and sex (PROC TABULATE) */
data dm;
  input USUBJID $ ARM $ SEX $;
  datalines;
01-001 DRUG M
01-002 DRUG F
01-003 PLACEBO M
01-004 DRUG M
;
run;
proc tabulate data=dm;
  class ARM SEX;
  table ARM, SEX*N;
run;
