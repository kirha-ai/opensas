/* expect-rc: 1 */
data chars;input s $;datalines;
A
B
;
run;
proc univariate data=chars;var _numeric_;run;
