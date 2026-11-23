data _null_; file print; put 'Case freq_binomial_sup'; run;
data sample;input x w;datalines;
1 7
2 13
;
run;
proc freq data=sample;weight w;tables x / binomial(sup p=0.2 margin=0.1 var=null);run;

data _null_; file print; put 'Case freq_binomial_superiority'; run;
data sample;input x w;datalines;
1 7
2 13
;
run;
proc freq data=sample;weight w;tables x / binomial(superiority p=0.2 margin=0.1 var=null);run;
