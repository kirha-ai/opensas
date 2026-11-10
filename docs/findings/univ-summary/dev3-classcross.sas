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
