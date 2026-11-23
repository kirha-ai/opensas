data _null_; file print; put 'Case freq_relrisk_sup_lr'; run;
data sample;input r c w;datalines;
1 1 12
1 2 8
2 1 5
2 2 25
;
run;
proc freq data=sample;weight w;tables r*c / noprint relrisk(sup margin=1.25 method=lr);run;

data _null_; file print; put 'Case freq_relrisk_sup_score'; run;
data sample;input r c w;datalines;
1 1 12
1 2 8
2 1 5
2 2 25
;
run;
proc freq data=sample;weight w;tables r*c / noprint relrisk(sup margin=1.25 method=score);run;

data _null_; file print; put 'Case freq_relrisk_sup_wald'; run;
data sample;input r c w;datalines;
1 1 12
1 2 8
2 1 5
2 2 25
;
run;
proc freq data=sample;weight w;tables r*c / noprint relrisk(sup margin=1.25 method=wald);run;

data _null_; file print; put 'Case freq_relrisk_sup_waldmodified'; run;
data sample;input r c w;datalines;
1 1 12
1 2 8
2 1 5
2 2 25
;
run;
proc freq data=sample;weight w;tables r*c / noprint relrisk(sup margin=1.25 method=waldmodified);run;
