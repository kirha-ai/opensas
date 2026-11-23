data d; input g r c w; datalines;
1 1 1 1
1 1 2 7
1 2 1 3
1 2 2 10
2 1 1 15
2 1 2 1
2 2 1 4
2 2 2 1
;
run;
ods output CommonOddsRatioTest=ct;
proc freq data=d; tables g*r*c; weight w/zeros; exact comor / point midp; run;
ods output close;
data _null_; set ct; if name1 ne ''; put 'FREQHAND|center-b|' name1 '|' nvalue1 best32.; run;
