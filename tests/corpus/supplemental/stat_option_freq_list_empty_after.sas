/* expect-rc: 1 */
data sample;input x01 extra x03 x02 s $ y;datalines;
1 9 3 2 A 5
3 11 5 4 B 7
;
run;
proc freq data=sample;tables x01 nothing:;run;
