options nodate nonumber nosyntaxcheck; ods graphics off;
data d; input r w; datalines;
1 20
2 27
3 23
;
data p; input _testp_ TestPercent Percent; datalines;
20 30 40
30 30 40
50 40 20
;
data p1; input _testp_; datalines;
20
30
50
;
title 'CASE SPLIT TESTP LIST';
proc freq data=d; weight w; tables r / testp=(20 30) testp=(50); run;
title 'CASE DATASET WITHOUT CHISQ';
proc freq data=d; weight w; tables r / testp=p1; run;
title 'CASE ALIAS PRIORITY WITH CHISQ';
proc freq data=d; weight w; tables r / chisq testp=p; run;
title 'CASE REPEATED DATASET';
proc freq data=d; weight w; tables r / chisq testp=p1 testp=p1; run;
title 'CASE LIST AND DATASET';
proc freq data=d; weight w; tables r / chisq testp=(20 30 50) testp=p1; run;
data p2; input _testp_; datalines;
40
40
20
;
title 'CASE DIFFERENT LIST THEN DATASET';
proc freq data=d; weight w; tables r / chisq testp=(20 30 50) testp=p2; run;
title 'CASE DIFFERENT DATASET THEN LIST';
proc freq data=d; weight w; tables r / chisq testp=p2 testp=(20 30 50); run;
title 'CASE TWO TABLES DIFFERENT DATASETS';
proc freq data=d; weight w; tables r / chisq testp=p1; tables r / chisq testp=p2; run;
