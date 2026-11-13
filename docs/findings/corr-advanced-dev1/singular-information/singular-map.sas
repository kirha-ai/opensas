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
ods output PolychoricCorr=o;proc corr data=d singular=0 polychoric(converge=.0001);var x y;freq f;run;data part;length case $40;set o;case="SING=0 C=.0001";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=d singular=0 polychoric(converge=.00001);var x y;freq f;run;data part;length case $40;set o;case="SING=0 C=.00001";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=d singular=1e-16 polychoric(converge=.0001);var x y;freq f;run;data part;length case $40;set o;case="SING=1e-16 C=.0001";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=d singular=1e-16 polychoric(converge=.00001);var x y;freq f;run;data part;length case $40;set o;case="SING=1e-16 C=.00001";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=d singular=1e-12 polychoric(converge=.0001);var x y;freq f;run;data part;length case $40;set o;case="SING=1e-12 C=.0001";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=d singular=1e-12 polychoric(converge=.00001);var x y;freq f;run;data part;length case $40;set o;case="SING=1e-12 C=.00001";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=d singular=1e-8 polychoric(converge=.0001);var x y;freq f;run;data part;length case $40;set o;case="SING=1e-8 C=.0001";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=d singular=1e-8 polychoric(converge=.00001);var x y;freq f;run;data part;length case $40;set o;case="SING=1e-8 C=.00001";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=d singular=.01 polychoric(converge=.0001);var x y;freq f;run;data part;length case $40;set o;case="SING=.01 C=.0001";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=d singular=.01 polychoric(converge=.00001);var x y;freq f;run;data part;length case $40;set o;case="SING=.01 C=.00001";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=d singular=.5 polychoric(converge=.0001);var x y;freq f;run;data part;length case $40;set o;case="SING=.5 C=.0001";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=d singular=.5 polychoric(converge=.00001);var x y;freq f;run;data part;length case $40;set o;case="SING=.5 C=.00001";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=d polychoric(converge=1e-5 maxiter=15);var x y;freq f;run;data part;length case $40;set o;case="DS=d M=15";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=d polychoric(converge=1e-5 maxiter=20);var x y;freq f;run;data part;length case $40;set o;case="DS=d M=20";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=d polychoric(converge=1e-5 maxiter=25);var x y;freq f;run;data part;length case $40;set o;case="DS=d M=25";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=d polychoric(converge=1e-5 maxiter=30);var x y;freq f;run;data part;length case $40;set o;case="DS=d M=30";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=d polychoric(converge=1e-5 maxiter=35);var x y;freq f;run;data part;length case $40;set o;case="DS=d M=35";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=d polychoric(converge=1e-5 maxiter=40);var x y;freq f;run;data part;length case $40;set o;case="DS=d M=40";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=d polychoric(converge=1e-5 maxiter=50);var x y;freq f;run;data part;length case $40;set o;case="DS=d M=50";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=d polychoric(converge=1e-5 maxiter=100);var x y;freq f;run;data part;length case $40;set o;case="DS=d M=100";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=d polychoric(converge=1e-5 maxiter=200);var x y;freq f;run;data part;length case $40;set o;case="DS=d M=200";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=tr polychoric(converge=1e-5 maxiter=15);var x y;freq f;run;data part;length case $40;set o;case="DS=tr M=15";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=tr polychoric(converge=1e-5 maxiter=20);var x y;freq f;run;data part;length case $40;set o;case="DS=tr M=20";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=tr polychoric(converge=1e-5 maxiter=25);var x y;freq f;run;data part;length case $40;set o;case="DS=tr M=25";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=tr polychoric(converge=1e-5 maxiter=30);var x y;freq f;run;data part;length case $40;set o;case="DS=tr M=30";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=tr polychoric(converge=1e-5 maxiter=35);var x y;freq f;run;data part;length case $40;set o;case="DS=tr M=35";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=tr polychoric(converge=1e-5 maxiter=40);var x y;freq f;run;data part;length case $40;set o;case="DS=tr M=40";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=tr polychoric(converge=1e-5 maxiter=50);var x y;freq f;run;data part;length case $40;set o;case="DS=tr M=50";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=tr polychoric(converge=1e-5 maxiter=100);var x y;freq f;run;data part;length case $40;set o;case="DS=tr M=100";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=tr polychoric(converge=1e-5 maxiter=200);var x y;freq f;run;data part;length case $40;set o;case="DS=tr M=200";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=scaled polychoric(converge=1e-5 maxiter=15);var x y;freq f;run;data part;length case $40;set o;case="DS=scaled M=15";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=scaled polychoric(converge=1e-5 maxiter=20);var x y;freq f;run;data part;length case $40;set o;case="DS=scaled M=20";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=scaled polychoric(converge=1e-5 maxiter=25);var x y;freq f;run;data part;length case $40;set o;case="DS=scaled M=25";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=scaled polychoric(converge=1e-5 maxiter=30);var x y;freq f;run;data part;length case $40;set o;case="DS=scaled M=30";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=scaled polychoric(converge=1e-5 maxiter=35);var x y;freq f;run;data part;length case $40;set o;case="DS=scaled M=35";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=scaled polychoric(converge=1e-5 maxiter=40);var x y;freq f;run;data part;length case $40;set o;case="DS=scaled M=40";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=scaled polychoric(converge=1e-5 maxiter=50);var x y;freq f;run;data part;length case $40;set o;case="DS=scaled M=50";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=scaled polychoric(converge=1e-5 maxiter=100);var x y;freq f;run;data part;length case $40;set o;case="DS=scaled M=100";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=scaled polychoric(converge=1e-5 maxiter=200);var x y;freq f;run;data part;length case $40;set o;case="DS=scaled M=200";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=held polychoric(converge=1e-5 maxiter=15);var x y;freq f;run;data part;length case $40;set o;case="DS=held M=15";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=held polychoric(converge=1e-5 maxiter=20);var x y;freq f;run;data part;length case $40;set o;case="DS=held M=20";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=held polychoric(converge=1e-5 maxiter=25);var x y;freq f;run;data part;length case $40;set o;case="DS=held M=25";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=held polychoric(converge=1e-5 maxiter=30);var x y;freq f;run;data part;length case $40;set o;case="DS=held M=30";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=held polychoric(converge=1e-5 maxiter=35);var x y;freq f;run;data part;length case $40;set o;case="DS=held M=35";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=held polychoric(converge=1e-5 maxiter=40);var x y;freq f;run;data part;length case $40;set o;case="DS=held M=40";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=held polychoric(converge=1e-5 maxiter=50);var x y;freq f;run;data part;length case $40;set o;case="DS=held M=50";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=held polychoric(converge=1e-5 maxiter=100);var x y;freq f;run;data part;length case $40;set o;case="DS=held M=100";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;
ods output PolychoricCorr=o;proc corr data=held polychoric(converge=1e-5 maxiter=200);var x y;freq f;run;data part;length case $40;set o;case="DS=held M=200";keep case Corr StdErr WaldChiSq LRChiSq;run;proc append base=results data=part;run;

ods exclude none;options linesize=240 pagesize=max;proc print data=results noobs;var case Corr StdErr WaldChiSq LRChiSq;format _numeric_ best32.;run;
