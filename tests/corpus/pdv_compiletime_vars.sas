/* BUG-pdvcompilevars: SAS builds the PDV at compile time — a variable named
   only in a never-executed statement (or a bare FORMAT statement) still
   exists, as missing-of-type. an EPOCH macro's partial-date vars rely
   on this: with full dates their branches never run, but the later PROC
   TRANSPOSE `var EV_DT2;` must still find the variable. */
data t2;
  x = '2023-05-01';
  if length(x) = 4 then ev2 = 1;   /* never true -> ev2 num, missing */
  if length(x) = 4 then s2 = cats('y', x); /* never true -> s2 char, blank */
  format ev3 8.;                   /* named ONLY here -> ev3 num, missing */
run;
proc transpose data=t2 out=o prefix=dt_;
  var ev2;
run;
proc print data=t2 noobs; run;
proc print data=o noobs; run;
