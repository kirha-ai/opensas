proc format;value grp 1,2='A' 3='B';run;
data sample;input g x f id;format g grp.;datalines;
1 10 0 101
2 20 1 102
2 30 1 103
3 40 1 104
;
run;
proc univariate data=sample noprint idout;by g;freq f;id id;var x;output out=o n=n mean=m;run;data _null_;set o;file print;put 'KEY ' g best4. '|' id '|' n '|' m;run;
