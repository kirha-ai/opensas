/* FEAT-freq-tests regression; expect-rc: 2 */
data d; input g h _testp_; datalines;
1 1 50
2 2 50
;
proc freq data=d; tables g*h / chisq; output out=o chisq; run;
