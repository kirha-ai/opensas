data n1;input x y f;datalines;
0 0 7
0 1 11
1 3 17
;
data n2;input x y f;datalines;
0 0 9
2 0 13
7 -1 21
;
data n3;input x y f;datalines;
1 1 1000
1 2 1
2 2 1000
2 3 1
3 3 1000
;
ods exclude all;
ods output PolychoricCorr=o;proc corr data=n1 polychoric(converge=.99 maxiter=200);var x;with y;freq f;run;data part;length tag $40;set o;tag="n1 C=.99 M=200";keep tag Corr StdErr LRChiSq;run;proc append base=result data=part;run;
ods output PolychoricCorr=o;proc corr data=n1 polychoric(converge=.01 maxiter=200);var x;with y;freq f;run;data part;length tag $40;set o;tag="n1 C=.01 M=200";keep tag Corr StdErr LRChiSq;run;proc append base=result data=part;run;
ods output PolychoricCorr=o;proc corr data=n1 polychoric(converge=.001 maxiter=200);var x;with y;freq f;run;data part;length tag $40;set o;tag="n1 C=.001 M=200";keep tag Corr StdErr LRChiSq;run;proc append base=result data=part;run;
ods output PolychoricCorr=o;proc corr data=n1 polychoric(converge=.0001 maxiter=200);var x;with y;freq f;run;data part;length tag $40;set o;tag="n1 C=.0001 M=200";keep tag Corr StdErr LRChiSq;run;proc append base=result data=part;run;
ods output PolychoricCorr=o;proc corr data=n1 polychoric(converge=.00001 maxiter=200);var x;with y;freq f;run;data part;length tag $40;set o;tag="n1 C=.00001 M=200";keep tag Corr StdErr LRChiSq;run;proc append base=result data=part;run;
ods output PolychoricCorr=o;proc corr data=n1 polychoric(converge=.000001 maxiter=200);var x;with y;freq f;run;data part;length tag $40;set o;tag="n1 C=.000001 M=200";keep tag Corr StdErr LRChiSq;run;proc append base=result data=part;run;
ods output PolychoricCorr=o;proc corr data=n2 polychoric(converge=.99 maxiter=200);var x;with y;freq f;run;data part;length tag $40;set o;tag="n2 C=.99 M=200";keep tag Corr StdErr LRChiSq;run;proc append base=result data=part;run;
ods output PolychoricCorr=o;proc corr data=n2 polychoric(converge=.01 maxiter=200);var x;with y;freq f;run;data part;length tag $40;set o;tag="n2 C=.01 M=200";keep tag Corr StdErr LRChiSq;run;proc append base=result data=part;run;
ods output PolychoricCorr=o;proc corr data=n2 polychoric(converge=.001 maxiter=200);var x;with y;freq f;run;data part;length tag $40;set o;tag="n2 C=.001 M=200";keep tag Corr StdErr LRChiSq;run;proc append base=result data=part;run;
ods output PolychoricCorr=o;proc corr data=n2 polychoric(converge=.0001 maxiter=200);var x;with y;freq f;run;data part;length tag $40;set o;tag="n2 C=.0001 M=200";keep tag Corr StdErr LRChiSq;run;proc append base=result data=part;run;
ods output PolychoricCorr=o;proc corr data=n2 polychoric(converge=.00001 maxiter=200);var x;with y;freq f;run;data part;length tag $40;set o;tag="n2 C=.00001 M=200";keep tag Corr StdErr LRChiSq;run;proc append base=result data=part;run;
ods output PolychoricCorr=o;proc corr data=n2 polychoric(converge=.000001 maxiter=200);var x;with y;freq f;run;data part;length tag $40;set o;tag="n2 C=.000001 M=200";keep tag Corr StdErr LRChiSq;run;proc append base=result data=part;run;
ods output PolychoricCorr=o;proc corr data=n3 polychoric(converge=.0001 maxiter=1);var x;with y;freq f;run;data part;length tag $40;set o;tag="n3 C=.0001 M=1";keep tag Corr StdErr LRChiSq;run;proc append base=result data=part;run;
ods output PolychoricCorr=o;proc corr data=n3 polychoric(converge=.0001 maxiter=2);var x;with y;freq f;run;data part;length tag $40;set o;tag="n3 C=.0001 M=2";keep tag Corr StdErr LRChiSq;run;proc append base=result data=part;run;
ods output PolychoricCorr=o;proc corr data=n3 polychoric(converge=.0001 maxiter=3);var x;with y;freq f;run;data part;length tag $40;set o;tag="n3 C=.0001 M=3";keep tag Corr StdErr LRChiSq;run;proc append base=result data=part;run;
ods output PolychoricCorr=o;proc corr data=n3 polychoric(converge=.00001 maxiter=1);var x;with y;freq f;run;data part;length tag $40;set o;tag="n3 C=.00001 M=1";keep tag Corr StdErr LRChiSq;run;proc append base=result data=part;run;
ods output PolychoricCorr=o;proc corr data=n3 polychoric(converge=.00001 maxiter=2);var x;with y;freq f;run;data part;length tag $40;set o;tag="n3 C=.00001 M=2";keep tag Corr StdErr LRChiSq;run;proc append base=result data=part;run;
ods output PolychoricCorr=o;proc corr data=n3 polychoric(converge=.00001 maxiter=3);var x;with y;freq f;run;data part;length tag $40;set o;tag="n3 C=.00001 M=3";keep tag Corr StdErr LRChiSq;run;proc append base=result data=part;run;
ods exclude none;options linesize=240 pagesize=max;proc print data=result noobs;format _numeric_ best32.;run;