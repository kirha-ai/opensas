data d;input x y f;datalines;
0 0 17
0 20 4
2 0 23
2 20 14
12 0 3
12 20 29
;
ods exclude all;
ods output PolychoricCorr=o;proc corr data=d polychoric(converge=.0002);var x;with y;freq f;run;data part;set o;cv=.0002;keep cv Corr StdErr;run;proc append base=result data=part;run;
ods output PolychoricCorr=o;proc corr data=d polychoric(converge=.00008);var x;with y;freq f;run;data part;set o;cv=.00008;keep cv Corr StdErr;run;proc append base=result data=part;run;
ods exclude none;options linesize=240 pagesize=max;proc print data=result noobs;format _numeric_ best32.;run;