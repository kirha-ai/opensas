/* GAP-fileio-batch-rest (pi-en): SET END= — the classic clinical idiom
   `set x end=last; if last then …` fires on the FINAL obs only, and `last`
   is a data-step temp: dropped from the output dataset like _N_. */
data x;
  input v;
  datalines;
10
20
30
;
run;

data _null_;
  set x end=last;
  if last then put "LAST v=" v;
  else put "row v=" v;
run;

/* temp var must not land in the output */
data y;
  set x end=last;
run;
proc print data=y noobs; run;
