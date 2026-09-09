/* DM: derive age group, cross-tab by sex (DATA step + PROC FREQ) */
data dm;
  input USUBJID $ SEX $ AGE ARM $;
  datalines;
01-001 M 45 DRUG
01-002 F 52 DRUG
01-003 M 38 PLACEBO
01-004 F 67 PLACEBO
01-005 M 71 DRUG
01-006 F 29 PLACEBO
;
run;

data dm2;
  set dm;
  length AGEGRP $8;
  if AGE < 40 then AGEGRP = "<40";
  else if AGE < 65 then AGEGRP = "40-64";
  else AGEGRP = ">=65";
run;

proc freq data=dm2;
  tables AGEGRP;
run;
