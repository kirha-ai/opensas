/* AE count per subject (multi-record BY-group, RETAIN counter) */
data ae;
  input USUBJID $ AETERM $;
  datalines;
01-001 HEADACHE
01-001 NAUSEA
01-001 RASH
01-002 FATIGUE
01-003 HEADACHE
01-003 DIZZINESS
;
run;

proc sort data=ae; by USUBJID; run;

data aecnt;
  set ae;
  by USUBJID;
  retain nae;
  if first.USUBJID then nae = 0;
  nae + 1;
  if last.USUBJID then output;
  keep USUBJID nae;
run;

proc print data=aecnt; run;
