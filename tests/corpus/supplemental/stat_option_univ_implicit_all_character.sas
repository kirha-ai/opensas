/* expect-rc: 1 */
data tags;input tag $ code $;datalines;
a x
b y
;
run;
proc univariate data=tags;run;
