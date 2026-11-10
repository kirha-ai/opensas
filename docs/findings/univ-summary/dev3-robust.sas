options nodate nonumber;
data d;input g x w;datalines;
1 7 1
2 3 1
2 9 1
3 5 1
3 5 1
3 5 1
4 -1 0
4 0 0
4 1 1
4 2 1
;
proc univariate data=d noprint outtable=t;by g;var x;run;
data _null_;set t;file print;put g= _MODE_= _GEOMEAN_= _HARMEAN_= _GINI_= _MAD_= _SN_= _QN_= _STDSN_= _STDQN_= _NORMAL_= _PROBN_=;run;
proc univariate data=d(where=(g=4)) noprint;var x;weight w;output out=o geomean=g harmean=h mean=m n=n;run;
data _null_;set o;file print;put g= h= m= n=;run;
