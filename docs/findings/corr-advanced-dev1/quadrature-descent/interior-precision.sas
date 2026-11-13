data a;input x y f;datalines;
0 0 17
0 20 4
2 0 23
2 20 14
12 0 3
12 20 29
;
proc corr data=a polychoric;var x;with y;freq f;run;
data b;input x y f;datalines;
0 0 26
0 3 13
0 23 4
7 0 3
7 3 18
7 23 31
;
proc corr data=b polychoric(converge=1e-6);var x;with y;freq f;run;
ods output PolychoricCorr=p;proc corr data=a polychoric;var x;with y;freq f;run;proc print data=p;format _numeric_ best32.;run;
ods output PolychoricCorr=p;proc corr data=b polychoric(converge=1e-6);var x;with y;freq f;run;proc print data=p;format _numeric_ best32.;run;