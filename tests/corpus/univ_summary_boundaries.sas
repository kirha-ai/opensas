options nodate nonumber;
data d;
input g x f;
y=2*x;id=_n_;
datalines;
1 10 1
2 90 0
1 20 1
2 90 -1
1 30 1
2 90 .
1 40 1
2 90 0.9
1 50 1
2 90 -0.5
1 60 1
2 90 0
1 70 1
;
run;
proc univariate data=d noprint idout outtable=t;
by g notsorted;var x y;freq f;id id;
output out=o n=nx ny mean=mx my;
run;
data _null_;set o;file print;put g= id= nx= ny= mx= my=;run;
data _null_;set t;file print;put g= _VAR_= _NOBS_= _MEAN_=;run;
data ids;
input id1 id2 x;
datalines;
101 201 10
102 202 20
103 203 30
;
run;
proc univariate data=ids noprint outtable=selected;id id:;run;
data _null_;set selected;file print;put _VAR_= _NOBS_= _MEAN_=;run;
