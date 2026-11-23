proc format;value names 1='Alpha' 2='Z';run;data d;input x n;format x names.;datalines;
1 3
2 7
;
run;
proc freq data=d;weight n;tables x/binomial(level='Z    suffix' p=.5);exact binomial / point;run;
