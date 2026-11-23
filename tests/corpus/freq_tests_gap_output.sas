/* SAS 9.4 M9 OUTPUT CHISQ on the two-observation diagonal table. */
data d; input g h _testp_; datalines;
1 1 50
2 2 50
;
proc freq data=d; tables g*h / chisq; output out=o chisq; run;
proc print data=o noobs; run;
