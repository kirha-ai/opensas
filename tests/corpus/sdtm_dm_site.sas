/* Extract site + subject number from USUBJID (char functions) */
data dm;
  input USUBJID $ ARM $;
  datalines;
01-001 DRUG
01-002 PLACEBO
02-011 DRUG
02-012 PLACEBO
;
run;

data sites;
  set dm;
  length site $2 subj $3;
  site = scan(USUBJID, 1, "-");
  subj = scan(USUBJID, 2, "-");
  armu = upcase(ARM);
run;

proc print data=sites; var USUBJID site subj armu; run;
