/* BUG-meansbypooled: PROC MEANS silently IGNORED the BY statement whenever
   there was MORE THAN ONE analysis variable or a CLASS statement — it printed
   ONE pooled table over ALL observations (a: N=4 Mean=25, b: N=4 Mean=250).
   SAS 9.4 prints one table PER BY GROUP: g=1 → a N=2 Mean=15, b Mean=150;
   g=2 → a N=2 Mean=35, b Mean=350. Same for CLASS: one class table per group. */
data d; input g a b; datalines;
1 10 100
1 20 200
2 30 300
2 40 400
;
run;
proc means data=d n mean; by g; var a b; run;

data c; input g h $ x; datalines;
1 P 10
1 Q 20
2 P 30
2 Q 40
;
run;
proc means data=c n mean sum; by g; class h; var x; run;
