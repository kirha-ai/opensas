/* BUG-meansbypooled regression lock (QA tick159): a BY group whose analysis
   variables are ALL MISSING must still print its own table with N=0 and the
   mean shown as "." — the per-BY-group iteration must not skip or merge it.
   g=1 has data (a mean 15, b mean 150); g=2 is all-missing (N=0, mean .). */
data d; input g a b; datalines;
1 10 100
1 20 200
2 . .
2 . .
;
run;
proc means data=d n mean; by g; var a b; run;
