data src;
  input x;
  datalines;
10
20
30
40
50
;
run;
/* obs=/firstobs= are INPUT-only: ignored on an OUTPUT dataset, ALL rows written */
data a(obs=2); set src; run;
data b(firstobs=3); set src; run;
/* INPUT-side control: set ... (obs=2) still reads 2 */
data c; set src(obs=2); run;
proc print data=a noobs; run;
proc print data=b noobs; run;
proc print data=c noobs; run;
