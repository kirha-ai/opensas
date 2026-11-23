data d; input g r c w; datalines;
1 1 1 254
1 1 2 1
1 2 1 1
1 2 2 0
2 1 1 1
2 1 2 255
2 2 1 0
2 2 2 1
3 1 1 1
3 1 2 3
3 2 1 2
3 2 2 6
;
run;
ods output CommonOddsRatioTest=ct;
proc freq data=d; tables g*r*c; weight w/zeros; exact comor / point midp; run;
ods output close;
data _null_; set ct; if name1 ne ''; put 'FREQHAND|near-farlo|' name1 '|' nvalue1 best32.; run;
