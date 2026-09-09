/* GAP-gapsexitingone §5d — the FILENAME concatenation form
   `filename ref ('a' 'b');` is documented valid SAS 9.4 (Language Reference: Concepts Table 21.5,
   cited at the guard) and opensas has no concat engine: valid SAS refused →
   gap → rc 2, not 1. The guard is the lparen itself, so no typo can reach it.
   expect-rc: 2 */
data a;
  x = 1;
run;
proc print data=a;
run;
filename both ('fa.txt' 'fb.txt');
