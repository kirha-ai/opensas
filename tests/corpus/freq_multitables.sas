data d;
  input g $ h $;
  datalines;
A X
A Y
B X
B Y
B Y
;
run;

/* BUG-freqmultitables: separate TABLES statements are separate tables.
   Two one-way tables (g, then h) — never a merged g*h crosstab. */
proc freq data=d;
  tables g;
  tables h;
run;

/* Per-statement options: / nocum scopes to its own statement only. */
proc freq data=d;
  tables g / nocum;
  tables h;
run;

/* Control: `*` WITHIN one statement is still a genuine two-way crosstab. */
proc freq data=d;
  tables g*h;
run;
