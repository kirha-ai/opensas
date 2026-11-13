data d;input x y f;datalines;
0 0 17
0 20 4
2 0 23
2 20 14
12 0 5
12 20 27
;
ods exclude all;
ods output PolychoricCorr=o;proc corr data=d polychoric(maxiter=3);var x;with y;freq f;run;data part;set o;limit=3;keep limit Corr StdErr;run;proc append base=result data=part;run;
ods output PolychoricCorr=o;proc corr data=d polychoric(maxiter=4);var x;with y;freq f;run;data part;set o;limit=4;keep limit Corr StdErr;run;proc append base=result data=part;run;
ods output PolychoricCorr=o;proc corr data=d polychoric(maxiter=5);var x;with y;freq f;run;data part;set o;limit=5;keep limit Corr StdErr;run;proc append base=result data=part;run;
ods output PolychoricCorr=o;proc corr data=d polychoric(maxiter=6);var x;with y;freq f;run;data part;set o;limit=6;keep limit Corr StdErr;run;proc append base=result data=part;run;
ods output PolychoricCorr=o;proc corr data=d polychoric(maxiter=7);var x;with y;freq f;run;data part;set o;limit=7;keep limit Corr StdErr;run;proc append base=result data=part;run;
ods exclude none;options linesize=240 pagesize=max;proc print data=result noobs;format _numeric_ best32.;run;