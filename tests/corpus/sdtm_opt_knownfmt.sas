/* With nofmterr set, KNOWN formats still render correctly (no false fallback) */
options nofmterr;
data d;
  dt = "04JUL2024"d;
  length sd $9 sc $10;
  sd = put(dt, date9.);
  sc = put(1234.5, dollar10.2);
  pc = put(0.25, percent8.);
run;
proc print data=d; var sd sc pc; run;
