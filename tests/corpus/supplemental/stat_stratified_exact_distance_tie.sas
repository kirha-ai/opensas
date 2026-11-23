data d; input g r c w; datalines;
1 1 1 0
1 1 2 1
1 2 1 2
1 2 2 89997
2 1 1 1
2 1 2 0
2 2 1 89997
2 2 2 2
3 1 1 1
3 1 2 0
3 2 1 0
3 2 2 1
;
run;
ods output CommonOddsRatioTest=ct;
proc freq data=d; tables g*r*c; weight w/zeros; exact comor / point midp; run;
ods output close;
data _null_; set ct; if name1 ne ''; put 'FREQHAND|exact-distance-tie|' name1 '|' nvalue1 best32.; run;
