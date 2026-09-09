/* GAP-wherenotinfix (doc-finder tick291 F6): the infix NOT before a
   comparison operator or before =* was unsupported, though both forms are
   documented and every sibling negation worked. Pins the Language Reference:
   Concepts p.226 rule: "You can use the NOT logical operator in combination
   with any SAS and WHERE expression operator" (e.g. `<var> not eq '<value>'
   or <num> not eq <n>`) and the p.224 sounds-like form `<var> not =* '<value>'`.
   Desugars to the negated operator (not eq -> ne, not gt -> le, …,
   not =* -> soundex ne soundex); a PREFIX not keeps SAS's Group-I precedence
   ((not x) eq 5), pinned below. */
data d; length tool $6; input tool $ level; datalines;
rust 5
rust 2
go 5
go 1
;
run;
/* the p.226 infix form — all four WHERE routes */
data r1; set d; where tool not eq 'rust' or level not eq 5; put 'STMT ' tool level; run;
data r2; set d(where=(tool not eq 'rust' or level not eq 5)); put 'OPT  ' tool level; run;
proc print data=d noobs; where tool not eq 'rust' or level not eq 5; run;
proc sql; select * from d where tool not eq 'rust' or level not eq 5; quit;
/* the p.224 sounds-like form — DATA-step and PROC SQL routes */
data r3; set d; where tool not =* 'rust'; put 'SND  ' tool level; run;
data r4; set d(where=(tool not =* 'rust')); put 'SNDO ' tool level; run;
proc print data=d noobs; where tool not =* 'rust'; run;
proc sql; select * from d where tool not =* 'rust'; quit;
/* the rest of the negation table, symbol forms included */
data r5; set d; where level not = 5;  put 'NE   ' tool level; run;
data r6; set d; where level not ne 2; put 'EQ   ' tool level; run;
data r7; set d; where level not gt 3; put 'LE   ' tool level; run;
data r8; set d; where level not ge 5; put 'LT   ' tool level; run;
data r9; set d; where level not lt 2; put 'GE   ' tool level; run;
data rA; set d; where level not le 1; put 'GT   ' tool level; run;
proc sql; select * from d where level not = 5; quit;
/* prefix NOT is a DIFFERENT expression and must keep SAS precedence:
   `not level eq 5` is (not level) eq 5 — false on every row here */
data rB; set d; where not level eq 5; put 'PFX  ' tool; run;
/* parenthesised prefix: not (level eq 5) = level ne 5 */
data rC; set d; where not (level eq 5); put 'PAR  ' tool level; run;
/* the six sibling negations that already worked — unchanged */
data s1; set d; where level not in (5);          put 'IN   ' tool level; run;
data s2; set d; where tool not contains 'us';    put 'CON  ' tool level; run;
data s3; set d; where tool not like 'r%';        put 'LIKE ' tool level; run;
data s4; set d; where level not between 3 and 5; put 'BTW  ' tool level; run;
data s5; set d; where tool is not missing;       put 'ISM  ' tool level; run;
