data sample;input r c w;datalines;
1 1 1
1 2 4
2 1 4
2 2 1
;
run;
proc freq data=sample ;weight w;tables r*c / chisq(warn=nolog);output out=stats chisq;run;
