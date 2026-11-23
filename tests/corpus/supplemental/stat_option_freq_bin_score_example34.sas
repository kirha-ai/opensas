data sample;input x w;datalines;
1 341
2 222
3 199
;
run;
proc freq data=sample order=freq;weight w;tables x / bin(cl=score) alpha=.1;run;
