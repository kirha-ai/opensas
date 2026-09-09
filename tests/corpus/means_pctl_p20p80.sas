/* GAP-meanspctlkeywords, half 2: P20/P30/P40/P60/P70/P80 are documented MEANS-
   family quantile keywords (Base SAS 9.4 Procedures Guide, PROC MEANS statement,
   printed pp.1491-1492; MEANS OUTPUT p.1504; REPORT p.2178; TABULATE p.2556) that
   nothing decoded, so `proc means p20` hit the warn-and-ignore arm and silently
   dropped the requested column. The doc BOUNDS the set — the quantile keyword
   table lists exactly P1/P5/P10/P20/P25(Q1)/P30/P40/P50/P60/P70/P75(Q3)/P80/P90/
   P95/P99 plus QRANGE — so exactly these six were added; arbitrary Pnn stays
   rejected (PCTLPTS= is SAS's door for that).

   ARM 1 is the listing: on x=1..100 (n=100, QNTLDEF=5) Pnn lands on an integer
   position, so the value is the average of the two straddling order statistics —
   P20=(20+21)/2=20.5, and likewise 30.5/40.5/60.5/70.5/80.5, the same shape the
   BUG-meanspctlmore fixture pins for P5=5.5.

   ARM 2 is MEANS OUTPUT OUT= on {2,4,4,4,5,5,7,9} (n=8): np = p/100*n is
   non-integer for all four, so the value is the ceil-position order statistic —
   P20=np 1.6→x2=4, P40=3.2→x4=4, P60=4.8→x5=5, P80=6.4→x7=7.

   The surface boundary is UNIVARIATE OUTPUT: Table 4.14 (Statistical Procedures,
   printed p.354) stops at P1/P5/P10/P25/P50/P75/P90/P95/P99, so p20= fails loud
   there (pinned by the in-file test next to the PRT guard test). */
data d;
  do i = 1 to 100; x = i; output; end;
run;
proc means data=d p20 p30 p40 p60 p70 p80; var x; run;

data m;
  input x @@;
  datalines;
2 4 4 4 5 5 7 9
;
run;
proc means data=m noprint;
  var x;
  output out=o p20=a p40=b p60=c p80=d;
run;
proc print data=o; run;
