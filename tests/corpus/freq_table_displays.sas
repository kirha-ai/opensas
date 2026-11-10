options nodate nonumber;
data d; input g h r c w; datalines;
1 1 10 2 3
1 1 10 4 1
1 1 20 2 2
2 2 20 4 4
2 2 30 6 0
2 2 . 2 2
;
run;
proc freq data=d; weight w; tables g*h*r*c / list; run;
proc freq data=d; weight w; tables g*h*r*c; run;
proc freq data=d; weight w / zeros; tables r*c / list sparse; tables r*c / crosslist nosparse; run;
proc freq data=d; weight w; tables g*r*c / expected deviation cellchi2 cumcol totpct missprint; run;
proc freq data=d; weight w; tables r*c / crosslist(pearsonres stdres) expected deviation cellchi2 missprint; run;
proc freq data=d; weight w; tables r / maxlevels=1 missprint; run;
proc freq data=d nlevels; weight w / zeros; tables r; run;
proc freq data=d formchar(1,2,7)='!=#'; weight w; tables r*c / format=6.1; run;
proc freq data=d;weight w;tables g*r*c / list line table;run;
proc freq data=d;weight w;tables r*c / nofreq;tables r*c / nofreq nopercent norow nocol;run;
proc freq data=d;weight w;tables g*h*r*c / crosslist;run;
data controlmiss;input g r c w;datalines;
. 1 1 2
1 1 1 3
1 2 2 1
;
run;
proc freq data=controlmiss;weight w;tables g*r*c / missprint totpct;run;
