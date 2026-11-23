data d;input g c x y;datalines;
1 2 1 1e155
1 1 1e155 2
1 1 1 1e155
1 2 1e155 2
2 2 1 1
2 1 1 1
3 2 1e155 2
3 1 1 1e155
3 2 1 1e155
3 1 1e155 2
;
run;proc univariate data=d noprint;class c(order=data);var x y;run;
