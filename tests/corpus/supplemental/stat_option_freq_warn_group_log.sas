data sample;input g x y w;datalines;
1 1 1 2
1 1 2 1
1 2 1 1
1 2 2 2
2 1 1 1
2 1 2 2
2 2 1 1
2 2 2 1
;
run;
proc freq data=sample noprint;weight w;tables g*x*y / chisq;output out=stats chisq;run;
