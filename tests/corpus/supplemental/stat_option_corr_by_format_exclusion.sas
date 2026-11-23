proc format;value grp 1,2='A' 3='B';run;
data sample;input g x f id;format g grp.;datalines;
1 10 0 101
2 20 1 102
2 30 1 103
3 40 1 104
;
run;
proc corr data=sample noprint outp=o;by g;freq f;var x;run;data _null_;set o;file print;if _type_='MEAN' then put 'KEY ' g best4. '|' x;run;
