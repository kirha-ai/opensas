/* Physical p.7850 DOLIST example; all null-case powers equal alpha exactly.
   Explicit ordering must survive the list/range syntax, including N=100. */
proc power;
 onesamplemeans mean=0 stddev=3 ntotal=30 to 70 by 20 100 power=.;
run;
