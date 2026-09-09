/* WHERE (pre-read) then subsetting IF (post-compute) narrow the set */
data ae;
  input USUBJID $ AESEV $ SERIOUS $;
  datalines;
01-001 MILD N
01-002 SEVERE Y
01-003 MODERATE N
01-004 SEVERE N
;
run;
data serious;
  set ae;
  where AESEV = "SEVERE";
  if SERIOUS = "Y";
run;
proc print data=serious; run;
