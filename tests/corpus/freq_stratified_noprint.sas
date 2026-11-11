ods graphics off;
data t;input r c n;datalines;
1 1 6
1 2 16
2 1 2
2 2 4
;
proc freq data=t noprint;weight n;tables r*c / agree cmh commonriskdiff;test kappa;run;
