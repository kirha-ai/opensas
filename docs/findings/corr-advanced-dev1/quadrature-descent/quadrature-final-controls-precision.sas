data c;input x y f;datalines;
0 0 11
0 2 4
0 7 3
1 0 5
1 2 17
1 7 6
9 0 2
9 2 7
9 7 19
;
proc corr data=c polychoric;var x;with y;freq f;run;
data e;input x y f;datalines;
-1 2 14
-1 11 9
3 2 6
3 11 23
;
proc corr data=e polychoric(converge=1e-6);var x;with y;freq f;run;
ods output PolychoricCorr=p;proc corr data=c polychoric;var x;with y;freq f;run;proc print data=p;format _numeric_ best32.;run;
ods output PolychoricCorr=p;proc corr data=e polychoric(converge=1e-6);var x;with y;freq f;run;proc print data=p;format _numeric_ best32.;run;