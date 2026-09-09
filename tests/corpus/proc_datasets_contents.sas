/* SE/DM end-of-program idiom: MODIFY label + ATTRIB strip + CONTENTS ... NOPRINT.
   CONTENTS is a display-only sub-statement (== PROC CONTENTS on the member);
   NOPRINT suppresses its listing. Synthesized (no PHI). Verifies PROC DATASETS
   accepts CONTENTS instead of "unsupported sub-statement". */
data d;
  input id age;
  format age 8.2;
  datalines;
1 30
2 45
;
run;
proc datasets lib=work memtype=data nolist nodetails;
  modify d (label='Demographics');
  attrib _all_ format=;
  contents data=d varnum noprint;
run;
quit;
proc print data=d noobs; run;
