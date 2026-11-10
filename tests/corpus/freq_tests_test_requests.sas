/* FEAT-freq-tests: TEST implication uses statement count, not expanded requests. */
options nodate nonumber; ods graphics off;
data cells; input r c q w; datalines;
1 1 1 12
1 2 2 5
2 1 2 4
2 2 1 17
;
proc freq data=cells; weight w; tables r*c r*q / noprint; test gamma; run;
proc freq data=cells; weight w; tables r*c / list; tables r*q / measures(cl) alpha=.1 noprint; test kentb stutc smdcr smdrc pcorr scorr; run;
proc freq data=cells; weight w; tables r*c / noprint; test taub tauc; run;
proc freq data=cells; weight w; test gamma; run;
proc freq data=cells; weight w; tables r*c; test; run;
