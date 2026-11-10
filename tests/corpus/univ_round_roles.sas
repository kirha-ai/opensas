options nodate nonumber;
data d;input g x;datalines;
1.1 10
1.2 20
;
proc univariate data=d noprint round=1;class g;var g;output out=c n=n mean=m;run;
data _null_;set c;file print;put 'CLASS ' g= n= m=;run;
proc univariate data=d noprint round=1;by g;var g;output out=b n=n mean=m;run;
data _null_;set b;file print;put 'BY ' g= n= m=;run;
proc univariate data=d noprint round=1;weight g;var g;output out=w n=n mean=m sumwgt=sw;run;
data _null_;set w;file print;put 'WEIGHT ' n= m= sw=;run;
