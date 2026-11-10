/* FEAT-freq-tests: manager onelevel and zero-total oracle boundaries. */
options nodate nonumber; ods graphics off;
data one; do i=1 to 3; g=1; output; end; run;
proc freq data=one; tables g / chisq(lrchi); run;
data zeros; input g w; datalines;
1 0
2 0
;
proc freq data=zeros; weight w / zeros; tables g / chisq; run;
proc freq data=zeros noprint; weight w / zeros; tables g / chisq(testp=(50 50) df=-1); run;
