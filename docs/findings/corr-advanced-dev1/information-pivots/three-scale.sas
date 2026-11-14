data d;input g case_id scale x y f;datalines;
1 3 1 0 0 35
1 3 1 0 -1 16
1 3 1 1 -1 23
1 3 1 1 -2 12
1 3 1 3 -2 24
2 3 100 0 0 3500
2 3 100 0 -1 1600
2 3 100 1 -1 2300
2 3 100 1 -2 1200
2 3 100 3 -2 2400
3 3 10000 0 0 350000
3 3 10000 0 -1 160000
3 3 10000 1 -1 230000
3 3 10000 1 -2 120000
3 3 10000 3 -2 240000
4 21 1 0 0 18
4 21 1 0 -20 28
4 21 1 0 -23 28
4 21 1 10 -23 38
5 21 100 0 0 1800
5 21 100 0 -20 2800
5 21 100 0 -23 2800
5 21 100 10 -23 3800
6 21 10000 0 0 180000
6 21 10000 0 -20 280000
6 21 10000 0 -23 280000
6 21 10000 10 -23 380000
7 22 1 0 0 10
7 22 1 0 1 32
7 22 1 10 1 38
7 22 1 20 1 10
8 22 100 0 0 1000
8 22 100 0 1 3200
8 22 100 10 1 3800
8 22 100 20 1 1000
9 22 10000 0 0 100000
9 22 10000 0 1 320000
9 22 10000 10 1 380000
9 22 10000 20 1 100000
;
ods exclude all;ods output PolychoricCorr=o;proc corr data=d polychoric(converge=1e-6);by g;var x;with y;freq f;run;ods exclude none;options linesize=240 pagesize=max;proc print data=o noobs;var g NObs Corr StdErr WaldChiSq LRChiSq;format _numeric_ best32.;run;
data _null_;file print;do p=10/90,42/90,80/90,51/110,86/110,35/110,74/110,18/112,46/112,74/112;z1=probit(p);z2=quantile("normal",p);diff=z1-z2;same=(z1=z2);put p=best32. z1=hex16. z2=hex16. diff=best32. same=;end;run;