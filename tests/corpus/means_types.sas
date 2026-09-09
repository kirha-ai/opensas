/* TYPES/WAYS restrict the CLASS combos MEANS reports (BUG-meanstypes,
   BUG-meansways): `types a;` → only the a-alone table; `ways 1;` → all 1-way
   tables; `types a*b;` → the named 2-way cross. Previously both statements
   fell into the catch-all and were silently ignored (full n-way cross). */
data d; input a b x; datalines;
1 1 10
1 2 20
2 1 30
;
run;
proc means data=d; class a b; types a; var x; run;
proc means data=d; class a b; ways 1; var x; run;
proc means data=d n mean; class a b; types a*b; var x; run;
