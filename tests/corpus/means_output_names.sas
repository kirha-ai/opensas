/* BUG-meansoutput: PROC MEANS OUTPUT omitted-name + /AUTONAME + FREQ stmt.
   (a) BUG-meansoutemptyname: `output out=o mean=;` (output name omitted) →
       SAS names the output var after the analysis var(s) → wide MEAN dataset,
       NOT the default 5-stat _STAT_ long form; a mixed `mean=mx max=` keeps
       the omitted-name max column (named x) instead of silently dropping it.
   (b) BUG-meansautoname: `/ autoname` → var_Stat names (x_Mean, x_Max).
   (c) BUG-meansfreqstmt: `freq f;` → each obs counts trunc(f) times:
       x=1(f2),2(f3),3(f1) → effective 1,1,2,2,2,3 → N=6 Sum=11 Mean=11/6.
   Hand-verified vs SAS 9.4 (Base Procedures Guide, MEANS OUTPUT/FREQ). */
data d; input x y f; datalines;
1 100 2
2 200 3
3 300 1
;
run;
/* (c) FREQ weights the listing stats */
proc means data=d n sum mean; freq f; var x; run;
/* (a) all names omitted → wide vars x y (means), one row */
proc means data=d noprint; var x y; output out=o1 mean=; run;
proc print data=o1 noobs; run;
/* (b) autoname → x_Mean x_Max */
proc means data=d noprint; var x; output out=o2 mean= max= / autoname; run;
proc print data=o2 noobs; run;
/* (c)+(a) FREQ also flows into OUTPUT: _FREQ_=6, x=11/6 */
proc means data=d noprint; freq f; var x; output out=o4 mean=; run;
proc print data=o4 noobs; run;
/* (a) mixed specs: the omitted-name max column survives, named after x */
data h; input g x @@; datalines;
1 10 1 20 2 30 2 40 2 50
;
run;
proc means data=h noprint; class g; var x; output out=o3 mean=mx max=; run;
proc print data=o3 noobs; run;
