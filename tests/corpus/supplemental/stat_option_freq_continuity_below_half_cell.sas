data d;input g h w;datalines;
0 0 3
0 1 4
1 0 3
1 1 5
;
run;ods output ChiSq=chi;proc freq data=d;weight w / zeros;tables g*h / chisq;run;ods output close;data _null_;set chi;if statistic='Continuity Adj. Chi-Square';file print;put 'CC_RAW ' value hex16.;run;
