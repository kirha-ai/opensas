options nodate nonumber;
ods graphics off;
data d;
 input g w;
 datalines;
1 0
2 0
;
run;
proc freq data=d; weight w / zeros; tables g / chisq; run;
