data sample; input x f; datalines;
1 7
2 13
;
run;

proc freq data=sample; weight f; tables x / binomial(cl=(wilson(correct))); run;
