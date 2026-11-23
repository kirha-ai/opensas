data _null_; file print; put 'Case freq_riskdiff_equiv_fm'; run;
data sample;input r c w;datalines;
1 1 12
1 2 8
2 1 5
2 2 25
;
run;
proc freq data=sample;weight w;tables r*c / noprint riskdiff(equiv method=fm margin=(-.1,.6));run;

data _null_; file print; put 'Case freq_riskdiff_equiv_ha'; run;
data sample;input r c w;datalines;
1 1 12
1 2 8
2 1 5
2 2 25
;
run;
proc freq data=sample;weight w;tables r*c / noprint riskdiff(equiv method=ha margin=(-.1,.6));run;

data _null_; file print; put 'Case freq_riskdiff_equiv_score'; run;
data sample;input r c w;datalines;
1 1 12
1 2 8
2 1 5
2 2 25
;
run;
proc freq data=sample;weight w;tables r*c / noprint riskdiff(equiv method=score margin=(-.1,.6));run;

data _null_; file print; put 'Case freq_riskdiff_equiv_wald'; run;
data sample;input r c w;datalines;
1 1 12
1 2 8
2 1 5
2 2 25
;
run;
proc freq data=sample;weight w;tables r*c / noprint riskdiff(equiv method=wald margin=(-.1,.6));run;
