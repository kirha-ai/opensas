data sample;input x9 x10 x11 x09 x009 x011;datalines;
9 10 11 19 109 111
10 11 12 20 110 112
;
run;
proc corr data=sample;var x09-x11;run;
