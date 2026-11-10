/* FREQ ORDER/NLEVELS/FORMCHAR and weighted empty-stratum regression.
   GAP-freq-table-complete now applies FORMCHAR. PAGE/COMPRESS are explicit
   paginated-destination gaps; specifying both is invalid SAS and is tested
   through captured diagnostics, not in this positive fixture. */
data d;
  input x;
  datalines;
2
1
2
;
run;
/* Implemented ORDER=FREQ, NLEVELS, and FORMCHAR. */
proc freq data=d formchar='|----|+|---' nlevels order=freq;
  tables x;
run;
/* implemented: NOPRINT suppresses the listing; OUT= still builds */
proc freq data=d noprint;
  tables x / out=xcounts;
run;
proc print data=xcounts;
run;
/* F5: zero-weight stratum h=A prints no table; h=B renders normally */
data w;
  input h $ g $ s $ wt;
  datalines;
A X Y 0
B X Y 5
;
run;
proc freq data=w;
  tables h*g*s;
  weight wt;
run;
/* `weight wt / zeros` re-includes the zero-weight stratum (SAS) */
proc freq data=w;
  tables h*g*s;
  weight wt / zeros;
run;
