data d;input x y f;datalines;
0 0 280
2 0 273
2 20 161
12 20 189
;
proc corr data=d polychoric(converge=.00045 maxiter=14);var x;with y;freq f;run;
proc corr data=d polychoric(converge=.00038 maxiter=15);var x;with y;freq f;run;
ods output PolychoricCorr=p;proc corr data=d polychoric(converge=.00045 maxiter=14);var x;with y;freq f;run;proc print data=p;format _numeric_ best32.;run;
ods output PolychoricCorr=p;proc corr data=d polychoric(converge=.00038 maxiter=15);var x;with y;freq f;run;proc print data=p;format _numeric_ best32.;run;