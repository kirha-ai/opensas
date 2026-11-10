options nodate nonumber;
data d; input b x1 x2 x3 w; datalines;
1 . 1 1 2
1 2 2 2 1
2 3 1 3 3
;
run;
title 'DEFAULT';proc freq data=d; weight w; by b; run;
title 'ONE NOFREQ';proc freq data=d; tables x1 / nofreq; run;
title 'RES ALONE';proc freq data=d; tables x1*x2 / pearsonres stdres; run;
title 'SCORES ALONE';proc freq data=d; tables x1*x2 / scorout scores=ridit; run;
title 'SPARSE NOSPARSE';proc freq data=d; tables x1*x2 / list sparse nosparse out=o; run; proc print data=o; run;
title 'MISSING TABLE SCORE';proc freq data=d; weight w; tables x1*x2 / missing chisq scorout; run;
title 'RANGE';proc freq data=d; tables (x1-x3)*b; run;
