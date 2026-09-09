/* Age-group decode with a PROC FORMAT VALUE range + put */
proc format;
  value agegrp low-17="PED" 18-64="ADULT" 65-high="ELDERLY";
run;
data dm;
  input USUBJID $ AGE;
  datalines;
01-001 12
01-002 45
01-003 70
;
run;
data grp;
  set dm;
  length band $8;
  band = put(AGE, agegrp.);
run;
proc print data=grp; var USUBJID AGE band; run;
