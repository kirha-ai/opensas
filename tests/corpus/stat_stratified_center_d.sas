data d; input g r c w; datalines;
1 1 1 2
1 1 2 1
1 2 1 1
1 2 2 12
2 1 1 2
2 1 2 3
2 2 1 9
2 2 2 2
;
run;
ods output CommonOddsRatioTest=ct;
proc freq data=d; tables g*r*c; weight w/zeros; exact comor / point midp; run;
ods output close;
data _null_; set ct; if name1 ne ''; put 'FREQHAND|center-d|' name1 '|' nvalue1 best32.; run;
