data ae;
  length usubjid $4 aesev $8;
  input usubjid $ aesev $ aerel;
  datalines;
S01 MILD 1
S02 SEVERE 2
S03 MODERATE 1
S04 MILD 3
;
run;
data sub;
  set ae;
  where aesev in ('MILD','SEVERE') and aerel <= 2;
run;
proc print data=sub noobs; run;
