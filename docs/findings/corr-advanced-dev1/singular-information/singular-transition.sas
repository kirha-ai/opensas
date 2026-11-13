data d;input x y f;datalines;
1 1 10
1 2 4
2 2 8
2 3 2
3 3 7
;
data tr;set d;t=x;x=y;y=t;run;
data scaled;set d;f=100*f;run;
data held;input x y f;datalines;
1 1 5
1 2 7
2 2 8
2 3 3
3 3 12
;
ods exclude all;
ods output PolychoricCorr=o;proc corr data=d polychoric(converge=.000085);var x y;freq f;run;data part;length case $40;set o;case="C=.000085";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=d polychoric(converge=.00007);var x y;freq f;run;data part;length case $40;set o;case="C=.00007";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=d polychoric(converge=.00006);var x y;freq f;run;data part;length case $40;set o;case="C=.00006";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=d polychoric(converge=.000052);var x y;freq f;run;data part;length case $40;set o;case="C=.000052";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=d polychoric(converge=.000046);var x y;freq f;run;data part;length case $40;set o;case="C=.000046";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=d polychoric(converge=.00004);var x y;freq f;run;data part;length case $40;set o;case="C=.00004";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=d polychoric(converge=.000036);var x y;freq f;run;data part;length case $40;set o;case="C=.000036";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=d polychoric(converge=.000032);var x y;freq f;run;data part;length case $40;set o;case="C=.000032";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=d polychoric(converge=.000029);var x y;freq f;run;data part;length case $40;set o;case="C=.000029";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=d polychoric(converge=.000026);var x y;freq f;run;data part;length case $40;set o;case="C=.000026";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=d polychoric(converge=.000024);var x y;freq f;run;data part;length case $40;set o;case="C=.000024";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=d polychoric(converge=.000022);var x y;freq f;run;data part;length case $40;set o;case="C=.000022";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=d polychoric(converge=.00002);var x y;freq f;run;data part;length case $40;set o;case="C=.00002";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods exclude none;options linesize=240 pagesize=max;proc print data=results noobs;var case Corr StdErr WaldChiSq LRChiSq;format _numeric_ best32.;run;