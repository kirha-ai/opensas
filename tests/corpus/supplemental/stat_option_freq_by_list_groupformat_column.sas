data sample;input g1 g3 g2 x;datalines;
1 1 1 2
1 1 1 4
1 1 2 10
1 1 2 14
;
run;
data named;set sample;groupformat=g2;run;proc freq data=named;by groupformat;tables x;run;
