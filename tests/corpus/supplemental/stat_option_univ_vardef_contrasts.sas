data _null_; file print; put 'Case univ_vardef_df'; run;
data sample; input x y w; datalines;
1 2 2
2 0 1
4 6 3
;
run;

proc univariate data=sample noprint vardef=df;
var x; weight w; output out=summary var=v; run;
data _null_; file print; set summary; put 'VAR ' v 24.12; run;

data _null_; file print; put 'Case univ_vardef_n'; run;
data sample; input x y w; datalines;
1 2 2
2 0 1
4 6 3
;
run;

proc univariate data=sample noprint vardef=n;
var x; weight w; output out=summary var=v; run;
data _null_; file print; set summary; put 'VAR ' v 24.12; run;

data _null_; file print; put 'Case univ_vardef_wdf'; run;
data sample; input x y w; datalines;
1 2 2
2 0 1
4 6 3
;
run;

proc univariate data=sample noprint vardef=wdf;
var x; weight w; output out=summary var=v; run;
data _null_; file print; set summary; put 'VAR ' v 24.12; run;

data _null_; file print; put 'Case univ_vardef_weight'; run;
data sample; input x y w; datalines;
1 2 2
2 0 1
4 6 3
;
run;

proc univariate data=sample noprint vardef=weight;
var x; weight w; output out=summary var=v; run;
data _null_; file print; set summary; put 'VAR ' v 24.12; run;

data _null_; file print; put 'Case univ_vardef_wgt'; run;
data sample; input x y w; datalines;
1 2 2
2 0 1
4 6 3
;
run;

proc univariate data=sample noprint vardef=wgt;
var x; weight w; output out=summary var=v; run;
data _null_; file print; set summary; put 'VAR ' v 24.12; run;
