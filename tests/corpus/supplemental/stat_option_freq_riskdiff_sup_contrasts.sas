data _null_; file print; put 'Case freq_riskdiff_sup_fm'; run;
data sample;input r c w;datalines;
1 1 12
1 2 8
2 1 5
2 2 25
;
run;
proc freq data=sample;weight w;tables r*c / noprint riskdiff(sup margin=0.2 method=fm);run;

data _null_; file print; put 'Case freq_riskdiff_sup_ha'; run;
data sample;input r c w;datalines;
1 1 12
1 2 8
2 1 5
2 2 25
;
run;
proc freq data=sample;weight w;tables r*c / noprint riskdiff(sup margin=0.2 method=ha);run;

data _null_; file print; put 'Case freq_riskdiff_sup_wald'; run;
data sample;input r c w;datalines;
1 1 12
1 2 8
2 1 5
2 2 25
;
run;
proc freq data=sample;weight w;tables r*c / noprint riskdiff(sup margin=0.2 method=wald);run;
