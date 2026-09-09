/* Special missing (.A) tags a not-done result distinct from a plain missing */
data lb;
  input USUBJID $ AVALraw ND $;
  AVAL = AVALraw;
  if ND = "ND" then AVAL = .A;
  datalines;
01-001 45 X
01-002 0 ND
01-003 30 X
;
run;
data d;
  set lb;
  length disp $4;
  if AVAL = .A then disp = "ND";
  else if AVAL = . then disp = "MISS";
  else disp = "OK";
  keep USUBJID AVAL disp;
run;
proc print data=d; run;
