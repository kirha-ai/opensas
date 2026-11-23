data _null_; file print; put 'Case freq_agreement_test_kappa'; run;
data sample;input x y w;datalines;
1 1 15
1 2 1
1 3 4
2 1 2
2 2 10
2 3 4
3 1 1
3 2 3
3 3 12
;
run;
proc freq data=sample;weight w / zeros;tables x*y / noprint agree(wt=fc nullkappa=.2);test kappa;run;

data _null_; file print; put 'Case freq_agreement_test_wtkap'; run;
data sample;input x y w;datalines;
1 1 15
1 2 1
1 3 4
2 1 2
2 2 10
2 3 4
3 1 1
3 2 3
3 3 12
;
run;
proc freq data=sample;weight w / zeros;tables x*y / noprint agree(wt=fc nullwtkappa=.3);test wtkap;run;

data _null_; file print; put 'Case freq_agreement_test_wtkappa'; run;
data sample;input x y w;datalines;
1 1 15
1 2 1
1 3 4
2 1 2
2 2 10
2 3 4
3 1 1
3 2 3
3 3 12
;
run;
proc freq data=sample;weight w / zeros;tables x*y / noprint agree(wt=fc nullwtkappa=.3);test wtkappa;run;
