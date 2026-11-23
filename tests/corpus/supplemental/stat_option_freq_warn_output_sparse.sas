data sample;input r c w;datalines;
1 1 1
1 2 4
2 1 4
2 2 1
;
run;
data sample;set sample;w=w*1;run;proc freq data=sample noprint;weight w;tables r*c / chisq(warn=output);output out=stats chisq;run;data _null_;file print;set stats;put 'FLAG ' warn_pchi 2.;run;
