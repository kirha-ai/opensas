/* BUG-sqlhavingismissing: HAVING <expr> IS [NOT] NULL|MISSING must filter like
   WHERE does ("IS NULL and IS MISSING are used in the WHERE, ON, and HAVING
   expressions" — SQL Procedure Components, "IS Operator"). Each HAVING form
   sits next to the equivalent WHERE form on the SAME data so the two surfaces
   cannot drift apart again. */
data d2; x=1; y=.; output; x=2; y=5; output; run;

/* aggregate arg, GROUP BY: group x=1 has max(y)=. -> only x=1 qualifies */
proc sql; select x from d2 group by x having max(y) is missing; quit;
proc sql; select x from d2 where y is missing; quit;

/* the negation must actually negate -> only x=2 */
proc sql; select x from d2 group by x having max(y) is not missing; quit;
proc sql; select x from d2 where y is not missing; quit;

/* IS NULL is the same predicate as IS MISSING */
proc sql; select x from d2 group by x having max(y) is null; quit;
proc sql; select x from d2 group by x having max(y) is not null; quit;

/* plain column, with GROUP BY: x is never missing -> empty */
proc sql; select x from d2 group by x having x is missing; quit;
proc sql; select x from d2 group by x having x is not missing; quit;

/* character column: a blank string is missing for char */
data d3; length c $3; x=1; c=''; output; x=2; c='ab'; output; run;
proc sql; select x from d3 group by x having c is missing; quit;
proc sql; select x from d3 where c is missing; quit;
proc sql; select x from d3 group by x having c is not missing; quit;

/* HAVING with no GROUP BY: the whole table is one group (max(y)=5) */
proc sql; select max(y) from d2 having max(y) is missing; quit;
proc sql; select max(y) from d2 having max(y) is not missing; quit;
