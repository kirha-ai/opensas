options nodate nonumber;
proc format;value band 1='A' 4='A' 2='B' 3='B';run;
data d;input c x f;format c band.;datalines;
4 40 0
2 20 1
1 10 1
3 30 1
;
proc univariate data=d noprint;class c;var x;output out=a mean=m;run;
data _null_;set a;raw=c;file print;put 'plain ' c= raw= m=;run;
proc univariate data=d noprint;class c;var x;freq f;output out=b mean=m;run;
data _null_;set b;raw=c;file print;put 'freq ' c= raw= m=;run;
proc univariate data=d noprint;class c(order=formatted);var x;output out=e mean=m;run;
data _null_;set e;raw=c;file print;put 'formatted ' c= raw= m=;run;
