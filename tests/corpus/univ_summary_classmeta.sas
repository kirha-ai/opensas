/* Oracle: dev3-classrep */
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

/* Oracle: dev3-classcross */
proc format;value band 1='A' 4='A' 2='B' 3='B';run;
data d;input b c h $ x;format c band.;datalines;
1 4 X 40
1 1 Y 10
1 2 X 20
1 3 Y 30
2 1 X 10
2 4 Y 40
2 3 X 30
2 2 Y 20
;
proc univariate data=d noprint;by b;class c h;var x;output out=o mean=m;run;
data _null_;set o;raw=c;file print;put b= c= raw= h= m=;run;

/* Oracle: dev3-classvar */
proc format;value single 1-2='A';run;
data d;input c;format c single.;datalines;
2
1
;
proc univariate data=d noprint;class c;var c;output out=o n=n mean=m;run;
proc print data=o;run;
