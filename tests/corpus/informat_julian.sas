/* BUG-julianinformat: JULIANw. as an INPUT-statement informat reads a packed
   Julian date (yyddd / yyyyddd) to a SAS day — it was whitelisted as "known"
   with no read branch, so the digits silently parsed as a plain number.
   (The INPUT() *function* half is dev-b's functions.zig routing — ticketed.) */
data _null_;
  infile datalines;
  input @1 a julian7. @9 b julian5.;
  put a= b=;
datalines;
1960011 60011
1960001 61365
2000366 60366
;
run;
data _null_;
  infile datalines;
  input @1 c julian7.; /* 1900 is not leap -> day 366 invalid -> missing */
  put c=;
datalines;
1900366
;
run;
