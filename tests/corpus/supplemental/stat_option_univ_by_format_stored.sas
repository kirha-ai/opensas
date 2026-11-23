proc format;value grp 1,2='Pooled label' 3='Third';run;
data sample;input g x;format g grp.;datalines;
1 1
1 3
2 5
2 7
3 9
3 11
;
run;
proc univariate data=sample;by g;var x;run;
