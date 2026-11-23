data d; input g r c w; datalines;
1 1 1 0
1 1 2 1
1 2 1 1
1 2 2 0
2 1 1 0
2 1 2 1
2 2 1 39433
2 2 2 60537
3 1 1 1
3 1 2 0
3 2 1 5554
3 2 2 94434
4 1 1 1
4 1 2 0
4 2 1 54994
4 2 2 44996
;
run;
ods output CommonOddsRatioTest=ct;
proc freq data=d; tables g*r*c; weight w/zeros; exact comor / point midp; run;
ods output close;
data _null_; set ct; if name1 ne ''; put 'FREQHAND|exact-distance-crt-c0m2r|' name1 '|' nvalue1 best32.; run;
