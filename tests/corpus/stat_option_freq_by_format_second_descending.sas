proc format;value grp 1,2='A' 3='B';run;
data sample;input g h x;format g grp.;datalines;
1 2 10
2 1 20
3 1 30
;
run;
proc freq data=sample;by g descending h;tables x;run;
