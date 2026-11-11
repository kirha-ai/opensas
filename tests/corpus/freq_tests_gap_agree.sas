/* FEAT-freq-tests regression; expect-rc: 0 */
ods graphics off;
data d; input g h _testp_; datalines;
1 1 50
2 2 50
;
proc freq data=d; tables g*h / agree; run;
