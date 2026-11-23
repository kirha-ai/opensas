/* expect-rc: 1 */
proc format;value mix 1,3='A' 2='B';run;data sample;input g x;format g mix.;datalines;
3 1
1 2
2 3
;
run;
proc freq data=sample;by g;tables x;run;
