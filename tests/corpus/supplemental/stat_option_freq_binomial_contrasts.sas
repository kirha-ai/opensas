data _null_; file print; put 'Case freq_binomial_ac'; run;
data sample; input x f; datalines;
1 7
2 13
;
run;

proc freq data=sample; weight f; tables x / binomial(cl=(ac)); run;

data _null_; file print; put 'Case freq_binomial_agresticoull'; run;
data sample; input x f; datalines;
1 7
2 13
;
run;

proc freq data=sample; weight f; tables x / binomial(cl=(agresticoull)); run;

data _null_; file print; put 'Case freq_binomial_blaker'; run;
data sample; input x f; datalines;
1 7
2 13
;
run;

proc freq data=sample; weight f; tables x / binomial(cl=(blaker)); run;

data _null_; file print; put 'Case freq_binomial_clopperpearson'; run;
data sample; input x f; datalines;
1 7
2 13
;
run;

proc freq data=sample; weight f; tables x / binomial(cl=(clopperpearson)); run;

data _null_; file print; put 'Case freq_binomial_exact'; run;
data sample; input x f; datalines;
1 7
2 13
;
run;

proc freq data=sample; weight f; tables x / binomial(cl=(exact)); run;

data _null_; file print; put 'Case freq_binomial_jeffreys'; run;
data sample; input x f; datalines;
1 7
2 13
;
run;

proc freq data=sample; weight f; tables x / binomial(cl=(jeffreys)); run;
