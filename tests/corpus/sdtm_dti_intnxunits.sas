/* INTNX across week / quarter / year (begin-aligned) + negative offset */
data d;
  ref = "15JUN2024"d;
  wk  = intnx("week", ref, 1, "b");
  qt  = intnx("qtr", ref, 1, "b");
  yr  = intnx("year", ref, 1, "b");
  prev = intnx("month", ref, -3, "b");
  format ref wk qt yr prev date9.;
run;
proc print data=d; var wk qt yr prev; run;
