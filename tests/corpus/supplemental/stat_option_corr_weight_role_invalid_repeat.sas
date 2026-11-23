/* expect-rc: 1 */
data sample;input x w1 w2 label $;datalines;
1 1 3 A
3 2 1 B
7 1 2 C
;
run;
proc corr data=sample;var x;weight w1;weight absent;run;
