data _null_; file print; put 'Case corr_vardef_df'; run;
data sample; input x y w; datalines;
1 2 2
2 0 1
4 6 3
;
run;

proc corr data=sample cov vardef=df; var x; with y; weight w; run;

data _null_; file print; put 'Case corr_vardef_n'; run;
data sample; input x y w; datalines;
1 2 2
2 0 1
4 6 3
;
run;

proc corr data=sample cov vardef=n; var x; with y; weight w; run;

data _null_; file print; put 'Case corr_vardef_wdf'; run;
data sample; input x y w; datalines;
1 2 2
2 0 1
4 6 3
;
run;

proc corr data=sample cov vardef=wdf; var x; with y; weight w; run;

data _null_; file print; put 'Case corr_vardef_weight'; run;
data sample; input x y w; datalines;
1 2 2
2 0 1
4 6 3
;
run;

proc corr data=sample cov vardef=weight; var x; with y; weight w; run;

data _null_; file print; put 'Case corr_vardef_wgt'; run;
data sample; input x y w; datalines;
1 2 2
2 0 1
4 6 3
;
run;

proc corr data=sample cov vardef=wgt; var x; with y; weight w; run;
