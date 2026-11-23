data roles;input g id x y f w;datalines;
1 8 2 20 1 1
1 9 4 40 1 1
;
run;
proc freq data=roles(keep=g w);by g;weight w;tables g;run;
