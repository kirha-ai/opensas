data d;input r c;datalines;
. 1
1 1
. 2
1 2
;
run;
proc freq data=d;tables r*c / chisq missing;run;
