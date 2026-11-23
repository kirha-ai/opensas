data _null_; file print; put 'Case freq_or_cl_lr'; run;
data sample;input r c w;datalines;
1 1 12
1 2 8
2 1 5
2 2 25
;
run;
proc freq data=sample;weight w;tables r*c / noprint or(cl=lr);run;

data _null_; file print; put 'Case freq_or_cl_wald'; run;
data sample;input r c w;datalines;
1 1 12
1 2 8
2 1 5
2 2 25
;
run;
proc freq data=sample;weight w;tables r*c / noprint or(cl=wald);run;

data _null_; file print; put 'Case freq_or_cl_waldmodified'; run;
data sample;input r c w;datalines;
1 1 12
1 2 8
2 1 5
2 2 25
;
run;
proc freq data=sample;weight w;tables r*c / noprint or(cl=waldmodified);run;
