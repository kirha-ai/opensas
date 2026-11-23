data _null_; file print; put 'Case freq_relrisk_equiv_fm'; run;
data sample;input r c w;datalines;
1 1 12
1 2 8
2 1 5
2 2 25
;
run;
proc freq data=sample;weight w;tables r*c / noprint relrisk(equiv method=fm margin=(.8,5));run;

data _null_; file print; put 'Case freq_relrisk_equiv_lr'; run;
data sample;input r c w;datalines;
1 1 12
1 2 8
2 1 5
2 2 25
;
run;
proc freq data=sample;weight w;tables r*c / noprint relrisk(equiv method=lr margin=(.8,5));run;

data _null_; file print; put 'Case freq_relrisk_equiv_score'; run;
data sample;input r c w;datalines;
1 1 12
1 2 8
2 1 5
2 2 25
;
run;
proc freq data=sample;weight w;tables r*c / noprint relrisk(equiv method=score margin=(.8,5));run;

data _null_; file print; put 'Case freq_relrisk_equiv_wald'; run;
data sample;input r c w;datalines;
1 1 12
1 2 8
2 1 5
2 2 25
;
run;
proc freq data=sample;weight w;tables r*c / noprint relrisk(equiv method=wald margin=(.8,5));run;

data _null_; file print; put 'Case freq_relrisk_equiv_waldmodified'; run;
data sample;input r c w;datalines;
1 1 12
1 2 8
2 1 5
2 2 25
;
run;
proc freq data=sample;weight w;tables r*c / noprint relrisk(equiv method=waldmodified margin=(.8,5));run;
