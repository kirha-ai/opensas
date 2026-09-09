data one; input v; datalines;
1
2
3
;
data two; input v; datalines;
2
3
;
data three; input v; datalines;
3
;
run;
/* INTERSECT binds tighter than UNION: one UNION (two INTERSECT three) = {1,2,3} */
proc sql; select v from one union select v from two intersect select v from three; quit;
/* CORRESPONDING on UNION aligns by name (b has columns swapped) */
data a; input id x; datalines;
1 10
2 20
;
data b; input x id; datalines;
99 2
88 5
;
run;
proc sql; select id, x from a union corr select x, id from b; quit;
