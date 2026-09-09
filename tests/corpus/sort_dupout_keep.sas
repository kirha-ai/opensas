/* DUPOUT=(keep=x) dataset options apply to the duplicates dataset, exactly
   like out=(keep=) (BUG-sortdupoutfamily F4) */
data d; input x v; datalines;
1 10
1 10
1 20
;
run;
proc sort data=d nodup dupout=g(keep=x) out=o; by x v; run;
proc print data=g; run;
proc print data=o; run;
