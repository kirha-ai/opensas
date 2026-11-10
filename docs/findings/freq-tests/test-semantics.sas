options nodate nonumber nosyntaxcheck; ods graphics off;
data d; input r c q w; datalines;
1 1 1 12
1 2 2 5
1 3 3 3
2 1 2 4
2 2 3 17
2 3 1 6
3 1 3 2
3 2 1 8
3 3 2 13
;
title 'CASE ONE STATEMENT TWO REQUESTS';
proc freq data=d; weight w; tables r*c r*q / noprint; test gamma; run;
title 'CASE TWO STATEMENTS';
proc freq data=d; weight w; tables r*c / noprint; tables r*q / measures noprint; test gamma; run;
title 'CASE REPEATED TEST';
proc freq data=d; weight w; tables r*c / noprint; test gamma; test pcorr; run;
title 'CASE NO TABLES';
proc freq data=d; weight w; test gamma; run;
title 'CASE TESTP ALONE';
proc freq data=d; weight w; tables r / testp=(20 30 50); run;
title 'CASE TESTP AND TESTF';
proc freq data=d; weight w; tables r / chisq testp=(20 30 50) testf=(14 21 35); run;
title 'CASE EMPTY TEST';
proc freq data=d; weight w; tables r*c / noprint; test; run;
