/* Synthetic public validation cases; SAS supports AGREE/OUTPUT but OpenSAS keeps named gaps. */
options nodate nonumber nosyntaxcheck; ods graphics off;
/* FEAT-freq-tests regression; expect-rc: 1 */
data d; input g h _testp_; datalines;
1 1 50
2 2 50
;
proc freq data=d; tables g / chisq(df=0); run;

/* FEAT-freq-tests regression; expect-rc: 1 */
data d; input g h _testp_; datalines;
1 1 50
2 2 50
;
proc freq data=d; tables g / testp=(20 20); run;

/* FEAT-freq-tests regression; expect-rc: 1 */
data d; input g h _testp_; datalines;
1 1 50
2 2 50
;
proc freq data=d; tables g*h; test gamma; test pcorr; run;

/* FEAT-freq-tests regression; expect-rc: 1 */
data d; input g h _testp_; datalines;
1 1 50
2 2 50
;
proc freq data=d; tables g / chisq(testp=d); run;

/* FEAT-freq-tests regression; expect-rc: 2 */
data d; input g h _testp_; datalines;
1 1 50
2 2 50
;
proc freq data=d; tables g*h / agree; run;

/* FEAT-freq-tests regression; expect-rc: 2 */
data d; input g h _testp_; datalines;
1 1 50
2 2 50
;
proc freq data=d; tables g*h / chisq; output out=o chisq; run;

