/* expect-rc: 1 */
data chars;input s $;datalines;
A
B
;
run;
proc freq data=chars;tables _numeric_;run;
