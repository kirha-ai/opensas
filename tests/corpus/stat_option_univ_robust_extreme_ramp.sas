data d;input z;x=z*1e308;datalines;
0.0
0.02
0.04
0.060000000000000005
0.08
0.1
0.12000000000000001
0.14
;
run;proc univariate data=d noprint;var x;output out=q gini=gi mad=ma sn=sn qn=qn std_gini=sg;run;data _null_;set q;a=gi/1e308;b=ma/1e308;c=sn/1e308;e=qn/1e308;f=sg/1e308;file print;put 'ROB ' a best24. ' ' b best24. ' ' c best24. ' ' e best24. ' ' f best24.;run;
