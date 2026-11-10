data d;input g x w f id;datalines;
1 10 1 1 101
1 20 2 1 102
;
proc univariate data=d noprint outtable=t;by g;id id;freq f;weight w;run;
proc print data=t;var _VAR_;run;
proc univariate data=d noprint pctldef=2;var x;weight w;output out=o q1=q;run;
proc contents data=o out=c noprint;run;
data _null_; length label $256; ds=open('o');label=attrc(ds,'label');file print;put label;rc=close(ds);run;
