data roles;input g id x y f w;datalines;
1 8 2 20 1 1
1 9 4 40 1 1
;
run;
ods select Moments;proc univariate data=roles;by g;id id;freq f;weight w;run;
