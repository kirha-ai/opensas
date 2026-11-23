data _null_; file print; put 'Case freq_binomial_likelihoodratio'; run;
data sample; input x f; datalines;
1 7
2 13
;
run;

proc freq data=sample; weight f; tables x / binomial(cl=(likelihoodratio)); run;

data _null_; file print; put 'Case freq_binomial_logit'; run;
data sample; input x f; datalines;
1 7
2 13
;
run;

proc freq data=sample; weight f; tables x / binomial(cl=(logit)); run;

data _null_; file print; put 'Case freq_binomial_lr'; run;
data sample; input x f; datalines;
1 7
2 13
;
run;

proc freq data=sample; weight f; tables x / binomial(cl=(lr)); run;

data _null_; file print; put 'Case freq_binomial_midp'; run;
data sample; input x f; datalines;
1 7
2 13
;
run;

proc freq data=sample; weight f; tables x / binomial(cl=(midp)); run;

data _null_; file print; put 'Case freq_binomial_noninf'; run;
data sample;input x w;datalines;
1 7
2 13
;
run;
proc freq data=sample;weight w;tables x / binomial(noninf p=0.5 margin=0.2 var=sample);run;

data _null_; file print; put 'Case freq_binomial_noninferiority'; run;
data sample;input x w;datalines;
1 7
2 13
;
run;
proc freq data=sample;weight w;tables x / binomial(noninferiority p=0.5 margin=0.2 var=sample);run;
