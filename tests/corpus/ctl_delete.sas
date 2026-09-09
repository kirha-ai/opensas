data kept;
  input usubjid $ aeser;
  if aeser = 0 then delete;
  datalines;
S01 1
S02 0
S03 1
S04 0
;
run;
proc print data=kept noobs; run;
