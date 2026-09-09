/* QA regression (BUG-meansweight fixed): PROC MEANS WEIGHT statement applies
   weighted stats — Mean=Sum(wx)/Sum(w), Sum=Sum(wx). */
data d; input v w; datalines;
10 1
20 2
30 3
;
run;
proc means data=d mean sum n; var v; weight w; run;
