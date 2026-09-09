/* Data-derived value drives a WHERE filter in a later PROC */
data _null_;
  call symputx("target", "SEVERE");
run;
data ae;
  input USUBJID $ AESEV $;
  datalines;
01-001 MILD
01-002 SEVERE
01-003 MODERATE
01-004 SEVERE
;
run;
proc print data=ae;
  where AESEV = "&target";
run;
