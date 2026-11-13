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
ods output PolychoricCorr=o;proc corr data=d polychoric(converge=1e-5 maxiter=21);var x y;freq f;run;data part;length case $40;set o;case="d M=21";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=d polychoric(converge=1e-5 maxiter=22);var x y;freq f;run;data part;length case $40;set o;case="d M=22";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=d polychoric(converge=1e-5 maxiter=23);var x y;freq f;run;data part;length case $40;set o;case="d M=23";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=d polychoric(converge=1e-5 maxiter=24);var x y;freq f;run;data part;length case $40;set o;case="d M=24";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=d polychoric(converge=1e-5 maxiter=25);var x y;freq f;run;data part;length case $40;set o;case="d M=25";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=tr polychoric(converge=1e-5 maxiter=21);var x y;freq f;run;data part;length case $40;set o;case="tr M=21";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=tr polychoric(converge=1e-5 maxiter=22);var x y;freq f;run;data part;length case $40;set o;case="tr M=22";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=tr polychoric(converge=1e-5 maxiter=23);var x y;freq f;run;data part;length case $40;set o;case="tr M=23";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=tr polychoric(converge=1e-5 maxiter=24);var x y;freq f;run;data part;length case $40;set o;case="tr M=24";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=tr polychoric(converge=1e-5 maxiter=25);var x y;freq f;run;data part;length case $40;set o;case="tr M=25";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=scaled polychoric(converge=1e-5 maxiter=21);var x y;freq f;run;data part;length case $40;set o;case="scaled M=21";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=scaled polychoric(converge=1e-5 maxiter=22);var x y;freq f;run;data part;length case $40;set o;case="scaled M=22";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=scaled polychoric(converge=1e-5 maxiter=23);var x y;freq f;run;data part;length case $40;set o;case="scaled M=23";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=scaled polychoric(converge=1e-5 maxiter=24);var x y;freq f;run;data part;length case $40;set o;case="scaled M=24";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=scaled polychoric(converge=1e-5 maxiter=25);var x y;freq f;run;data part;length case $40;set o;case="scaled M=25";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=held polychoric(converge=1e-5 maxiter=21);var x y;freq f;run;data part;length case $40;set o;case="held M=21";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=held polychoric(converge=1e-5 maxiter=22);var x y;freq f;run;data part;length case $40;set o;case="held M=22";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=held polychoric(converge=1e-5 maxiter=23);var x y;freq f;run;data part;length case $40;set o;case="held M=23";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=held polychoric(converge=1e-5 maxiter=24);var x y;freq f;run;data part;length case $40;set o;case="held M=24";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=held polychoric(converge=1e-5 maxiter=25);var x y;freq f;run;data part;length case $40;set o;case="held M=25";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=held polychoric(converge=1e-6);var x y;freq f;run;data part;length case $40;set o;case="held C=1e-6";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=held polychoric(converge=1e-8);var x y;freq f;run;data part;length case $40;set o;case="held C=1e-8";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=held polychoric(converge=1e-12);var x y;freq f;run;data part;length case $40;set o;case="held C=1e-12";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods exclude none;options linesize=240 pagesize=max;proc print data=results noobs;var case Corr StdErr WaldChiSq LRChiSq;format _numeric_ best32.;run;