/* expect-rc: 1 */
data tags;input tag $ code $;datalines;
a x
b y
;
run;
proc corr data=tags;run;
