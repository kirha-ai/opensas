data d; input g r c w; datalines;
1 1 1 0
1 1 2 1
1 2 1 1
1 2 2 0
2 1 1 1
2 1 2 798
2 2 1 0
2 2 2 1
3 1 1 0
3 1 2 898
3 2 1 1
3 2 2 129
;
run;
ods output CommonOddsRatioTest=ct CommonOddsRatioCL=cl;
proc freq data=d; tables g*r*c; weight w/zeros; exact comor / point midp; run;
ods output close;
data _null_; set ct; if name1 ne ''; put 'FREQHAND|overflow-bound-rowflip|' name1 '|' nvalue1 best32.; run;
data _null_; set cl; if name1 in ('XL_COMOR','XU_COMOR'); put 'FREQHAND|overflow-bound-rowflip|' name1 '|' nvalue1 best32.; run;
