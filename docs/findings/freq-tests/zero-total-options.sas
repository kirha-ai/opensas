options nodate nonumber nosyntaxcheck; ods graphics off;
data d; input g w; datalines;
1 0
2 0
;
title 'CASE ZERO VALID TESTP';
proc freq data=d; weight w / zeros; tables g / chisq(lrchi testp=(50 50)); run;
title 'CASE ZERO BAD TESTP SUM';
proc freq data=d; weight w / zeros; tables g / chisq(testp=(20 20)); run;
title 'CASE ZERO BAD TESTP COUNT';
proc freq data=d; weight w / zeros; tables g / chisq(testp=(100)); run;
title 'CASE ZERO POSITIVE TESTF';
proc freq data=d; weight w / zeros; tables g / chisq(testf=(1 1)); run;
title 'CASE ZERO NEGATIVE DF';
proc freq data=d; weight w / zeros; tables g / chisq(df=-1); run;
title 'CASE ZERO EXPLICIT DF ZERO';
proc freq data=d; weight w / zeros; tables g / chisq(df=0); run;
