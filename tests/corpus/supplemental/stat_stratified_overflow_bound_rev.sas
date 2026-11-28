data d; input g r c w; datalines;
1 1 1 1
1 1 2 0
1 2 1 0
1 2 2 1
2 1 1 798
2 1 2 1
2 2 1 1
2 2 2 0
3 1 1 513
3 1 2 1
3 2 1 514
3 2 2 0
;
run;
ods output CommonOddsRatioTest=ct CommonOddsRatioCL=cl;
proc freq data=d; tables g*r*c; weight w/zeros; exact comor / point midp; run;
ods output close;
data _null_; set ct; if name1 ne ''; put 'FREQHAND|overflow-bound-rev|' name1 '|' nvalue1 best32.; run;
data _null_; set cl; if name1 in ('XL_COMOR','XU_COMOR'); put 'FREQHAND|overflow-bound-rev|' name1 '|' nvalue1 best32.; run;
/* STAT-BEST-001: BEST32. shows at most 16 characters besides the sign, so at
   M0_COMOR's magnitude it prints 10 decimals and cannot carry a 1e-12 check.
   M0_COMOR-1312 is exact in binary (Sterbenz) and BEST32. shows it to 1e-14. */
data _null_; set ct; if name1='M0_COMOR'; d=nvalue1-1312; put 'FREQHAND|overflow-bound-rev|M0_COMOR-1312|' d best32.; run;
