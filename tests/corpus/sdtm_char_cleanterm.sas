/* Normalize a verbatim AE term (STRIP/TRANWRD/PROPCASE) */
data ae; input RAW $30.; datalines;
head_ache
NAUSEA
diarrhea_severe
;
run;
data clean;
  set ae;
  length term $30;
  term = propcase(tranwrd(strip(RAW), "_", " "));
run;
proc print data=clean; var term; run;
