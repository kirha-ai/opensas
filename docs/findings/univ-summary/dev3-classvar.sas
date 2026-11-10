proc format;value band 1-2='A';run;
data d;input c;format c band.;datalines;
2
1
;
proc univariate data=d noprint;class c;var c;output out=o n=n mean=m;run;
proc print data=o;run;
