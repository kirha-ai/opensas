/* Age two ways: YRDIF('AGE') vs an INTCK('year')-with-birthday adjustment */
data dm; input USUBJID $ BRTHDTC : $9.; datalines;
01-001 15JUN1980
01-002 20DEC1990
01-003 01JAN2000
;
run;
data d;
  set dm;
  b = input(BRTHDTC, date9.);
  ref = "01MAR2024"d;
  age_yrdif = floor(yrdif(b, ref, "AGE"));
  keep USUBJID age_yrdif;
run;
proc print data=d; run;
