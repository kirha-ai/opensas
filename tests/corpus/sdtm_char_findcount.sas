/* Digit position and count in a code string (FINDC/COUNTC/COMPRESS) */
data lb; input CODE $12.; datalines;
LB001A2B3
VS999
NODIGITS
;
run;
data d;
  set lb;
  firstdig = findc(CODE, "0123456789");
  ndigit   = countc(CODE, "0123456789");
  letters  = compress(CODE, "0123456789");
run;
proc print data=d; var CODE firstdig ndigit letters; run;
