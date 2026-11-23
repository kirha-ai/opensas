/* expect-rc: 1 */
data roles;input g id x y f w;datalines;
1 8 2 20 1 1
1 9 4 40 1 1
;
run;
proc univariate data=roles(keep=g id f w);by g;id id;freq f;weight w;run;
