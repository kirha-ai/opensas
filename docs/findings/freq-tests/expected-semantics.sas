options nodate nonumber nosyntaxcheck; ods graphics off;
data d; input r c w; datalines;
1 1 12
1 2 5
1 3 3
2 1 4
2 2 17
2 3 6
3 1 2
3 2 8
3 3 13
;
title 'CASE TESTF ALONE';
proc freq data=d; weight w; tables r / testf=(14 21 35); run;
title 'CASE REPEATED TESTP';
proc freq data=d; weight w; tables r / testp=(20 30 50) testp=(30 30 40); run;
title 'CASE TWO WAY TESTP LIST';
proc freq data=d; weight w; tables r*c / testp=(20 30 50) noprint; run;
title 'CASE TWO WAY TESTP DATASET';
proc freq data=d; weight w; tables r*c / testp=absent noprint; run;
data p; input _testp_ TestPercent Percent; datalines;
20 30 40
30 30 40
50 40 20
;
title 'CASE SECONDARY ALIAS PRECEDENCE';
proc freq data=d; weight w; tables r / testp=p; run;
