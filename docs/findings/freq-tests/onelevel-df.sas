options nodate nonumber nosyntaxcheck; ods graphics off;
data d; do i=1 to 3; g=1; output; end; run;
proc freq data=d; tables g / chisq(lrchi testp=(100)); run;
proc freq data=d; tables g / chisq(lrchi df=2); run;
proc freq data=d; tables g / chisq(df=-1); run;
proc freq data=d; tables g / chisq(df=0); run;
