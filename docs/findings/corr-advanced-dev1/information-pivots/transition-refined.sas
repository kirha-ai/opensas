data d;input g x y f;datalines;
1 0 0 80
1 0 1 256
1 10 1 304
1 20 1 80
2 0 0 100
2 0 1 320
2 10 1 380
2 20 1 100
3 0 0 110
3 0 1 352
3 10 1 418
3 20 1 110
4 0 0 120
4 0 1 384
4 10 1 456
4 20 1 120
5 0 0 130
5 0 1 416
5 10 1 494
5 20 1 130
6 0 0 200
6 0 1 640
6 10 1 760
6 20 1 200
7 0 0 115
7 0 1 368
7 10 1 437
7 20 1 115
;
ods exclude all;
ods output PolychoricCorr=o;proc corr data=d  polychoric(converge=1e-6);by g;var x;with y;freq f;run;data p;length setting $8;set o;setting="default";keep setting g NObs Corr StdErr;run;proc append base=all data=p;run;
ods output PolychoricCorr=o;proc corr data=d singular=1e-16 polychoric(converge=1e-6);by g;var x;with y;freq f;run;data p;length setting $8;set o;setting="tiny";keep setting g NObs Corr StdErr;run;proc append base=all data=p;run;
ods output PolychoricCorr=o;proc corr data=d singular=.5 polychoric(converge=1e-6);by g;var x;with y;freq f;run;data p;length setting $8;set o;setting="large";keep setting g NObs Corr StdErr;run;proc append base=all data=p;run;
ods exclude none;options linesize=240 pagesize=max;proc print data=all noobs;format _numeric_ best32.;run;