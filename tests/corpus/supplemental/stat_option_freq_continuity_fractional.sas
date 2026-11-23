data d;input g h w;datalines;
0 0 0.25
0 1 2.5
1 0 3.25
1 1 0.5
;
run;ods output ChiSq=chi;proc freq data=d;weight w / zeros;tables g*h / chisq;run;ods output close;data _null_;set chi;if statistic='Continuity Adj. Chi-Square';file print;put 'CC_RAW ' value hex16.;run;
