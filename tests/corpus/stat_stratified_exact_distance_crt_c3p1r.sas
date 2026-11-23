data d; input g r c w; datalines;
1 1 1 0
1 1 2 1
1 2 1 1
1 2 2 0
2 1 1 0
2 1 2 1
2 2 1 108606
2 2 2 2424
3 1 1 1
3 1 2 0
3 2 1 59048
3 2 2 51970
4 1 1 1
4 1 2 0
4 2 1 53893
4 2 2 56103
;
run;
ods output CommonOddsRatioTest=ct;
proc freq data=d; tables g*r*c; weight w/zeros; exact comor / point midp; run;
ods output close;
data _null_; set ct; if name1 ne ''; put 'FREQHAND|exact-distance-crt-c3p1r|' name1 '|' nvalue1 best32.; run;
