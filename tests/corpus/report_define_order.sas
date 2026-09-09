/* tick240 PROC REPORT DEFINE options — three previously-broken faces of the
   permissive DEFINE-option scan, now honored (hand-verified):
     F1 GROUP DESCENDING — group levels descend C,B,A (was always ascending).
     F3 ORDER=FREQ       — group levels by descending frequency B,C,A.
     F4 NOPRINT          — v is summed for grouping but its column is omitted.
   Group sums: A=1, B=2+3+4=9, C=5+6=11. */
data d; input g $ v; datalines;
A 1
B 2
B 3
B 4
C 5
C 6
;
run;
proc report data=d nowd;
  column g v;
  define g / group descending;
  define v / analysis sum;
run;
proc report data=d nowd;
  column g v;
  define g / group order=freq;
  define v / analysis sum;
run;
proc report data=d nowd;
  column g v;
  define g / group;
  define v / analysis sum noprint;
run;
