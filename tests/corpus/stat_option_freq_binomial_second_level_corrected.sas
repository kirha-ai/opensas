data sample; input x f; datalines;
1 7
2 13
;
run;
proc freq data=sample;weight f;tables x / binomial(level=2 p=1 correct cl=(wald wilson));run;
