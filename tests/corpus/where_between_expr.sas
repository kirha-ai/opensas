/* BUG-wherebetweenexpr (doc-finder tick291 F3): BETWEEN…AND bounds were scanned
   as ONE token — `between 1 and 3+1` silently matched EVERY row, and the doc's
   own expression-bounds example died with an UNREPORTED ParseError. Language Reference: Concepts
   p.221 documents that the limits of the range may be constants or expressions.
   Parenthesised bounds already worked; unparenthesised must agree. */
data d; input dose weight; datalines;
80000 12000
80000 26000
80000 52000
;
run;
/* expression bounds on both sides — all four WHERE routes */
data r; set d; where weight between dose*0.25 and dose*0.45; run;
proc print data=r noobs; run;
data r2; set d(where=(weight between dose*0.25 and dose*0.45)); run;
proc print data=r2 noobs; run;
proc print data=d noobs; where weight between dose*0.25 and dose*0.45; run;
proc sql; select * from d where weight between dose*0.25 and dose*0.45; quit;
/* the parenthesised control (was already correct) must agree */
proc print data=d noobs; where weight between (dose*0.25) and (dose*0.45); run;
/* an arithmetic high bound: 1..(3+1) — used to match EVERY row */
data n; input x; datalines;
1
2
3
4
5
9
;
run;
data m; set n; where x between 1 and 3+1; run;
proc print data=m noobs; run;
proc sql; select * from n where x between 1 and 3+1; quit;
proc print data=n noobs; where x not between 1 and 3+1; run;
/* a computed bound on BOTH sides, and the BETWEEN-AND/logical-AND boundary */
proc sql; select * from n where x between 1+1 and 2*2; quit;
proc print data=n noobs; where x between 1 and 3 and x ne 2; run;
