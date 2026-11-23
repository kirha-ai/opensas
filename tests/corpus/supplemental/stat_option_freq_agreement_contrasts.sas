data _null_; file print; put 'Case freq_agreement_ac1'; run;
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
proc freq data=sample;weight w / zeros;tables x*y / noprint agree(ac1);run;

data _null_; file print; put 'Case freq_agreement_details'; run;
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
proc freq data=sample;weight w / zeros;tables x*y / noprint agree(wt=fc details);run;

data _null_; file print; put 'Case freq_agreement_dfsym'; run;
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
data sample;set sample;if (x=1 and y=3) or (x=3 and y=1) then w=0;run;proc freq data=sample;weight w / zeros;tables x*y / noprint agree(dfsym=adjust);run;

data _null_; file print; put 'Case freq_agreement_kappadetails'; run;
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
proc freq data=sample;weight w / zeros;tables x*y / noprint agree(wt=fc kappadetails);run;

data _null_; file print; put 'Case freq_agreement_pabak'; run;
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
proc freq data=sample;weight w / zeros;tables x*y / noprint agree(pabak);run;

data _null_; file print; put 'Case freq_agreement_restore'; run;
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
proc freq data=sample;weight w / zeros;tables x*y / noprint agree(tables=restore);test kappa;run;
