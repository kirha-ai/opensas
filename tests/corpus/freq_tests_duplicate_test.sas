/* FEAT-freq-tests regression; expect-rc: 1 */
data d; input g h _testp_; datalines;
1 1 50
2 2 50
;
proc freq data=d; tables g*h; test gamma; test pcorr; run;
