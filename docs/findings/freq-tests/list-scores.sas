options nodate nonumber nosyntaxcheck; ods graphics off;
data d; input r c w; datalines;
1 2 12
1 7 5
1 40 3
10 2 4
10 7 17
10 40 6
100 2 2
100 7 8
100 40 13
;
title 'CASE LIST CHISQ';
proc freq data=d; weight w; tables r*c / list chisq; run;
title 'CASE ONE WAY LIST CHISQ';
proc freq data=d; weight w; tables r / list chisq; run;
title 'CASE LIST IMPLIED TEST';
proc freq data=d; weight w; tables r*c / list; test gamma; run;
title 'CASE PROC NOPRINT LIST CHISQ';
proc freq data=d noprint; weight w; tables r*c / list chisq; run;
title 'CASE SEPARATE LIST AND STATISTICS';
proc freq data=d; weight w; tables r*c / list; tables r*c / measures noprint; test gamma; run;
title 'CASE TABLE SCORES';
proc freq data=d; weight w; tables r*c / chisq measures scores=table scorout noprint; test pcorr; run;
title 'CASE RANK SCORES';
proc freq data=d; weight w; tables r*c / chisq measures scores=rank scorout noprint; test pcorr; run;
title 'CASE RIDIT SCORES';
proc freq data=d; weight w; tables r*c / chisq measures scores=ridit scorout noprint; test pcorr; run;
title 'CASE MODRIDIT SCORES';
proc freq data=d; weight w; tables r*c / chisq measures scores=modridit scorout noprint; test pcorr; run;
