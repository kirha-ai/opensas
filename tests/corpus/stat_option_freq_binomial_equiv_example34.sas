data sample;input x w;datalines;
1 228
2 217
3 182
4 113
5 22
;
run;
proc freq data=sample order=freq;weight w;tables x / binomial(equiv p=.28 margin=.1);run;
