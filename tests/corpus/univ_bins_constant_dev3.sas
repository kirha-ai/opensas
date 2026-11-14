options nonumber nodate;
data d;
input g x @@;
datalines;
1 0 1 0 2 .01 2 .01 3 -1 3 -1 4 1234 4 1234 5 12.345 5 12.345
;
run;
proc univariate data=d noprint;
by g;
histogram x / noplot outhistogram=h;
histogram x / noplot endpoints outhistogram=e;
histogram x / noplot endpoints rtinclude outhistogram=r;
run;
data a; set h; kind='MID'; point=_midpt_; keep g kind point _obspct_ _count_; run;
data b; set e; kind='END'; point=_minpt_; keep g kind point _obspct_ _count_; run;
data c; set r; kind='RGT'; point=_maxpt_; keep g kind point _obspct_ _count_; run;
data _null_; set a b c; file print;
put kind $3. ' ' g 1. ' ' point 12.5 ' ' _obspct_ 8.2 ' ' _count_ 4.;
run;
