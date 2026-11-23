data d; input g r c w; datalines;
1 1 1 6
1 1 2 13
1 2 1 2
1 2 2 0
2 1 1 1
2 1 2 15
2 2 1 0
2 2 2 5
;
run;
ods output CommonOddsRatioTest=ct;
proc freq data=d; tables g*r*c; weight w/zeros; exact comor / point midp; run;
ods output close;
data _null_; set ct; if name1 ne ''; put 'FREQHAND|center-aleft|' name1 '|' nvalue1 best32.; run;
