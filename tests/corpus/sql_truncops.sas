/* GAP-sqltruncops — PROC SQL's alphabetic truncated-comparison operators
   (SQL Procedure User's Guide 4th ed, Table 8.2 group 7, printed p.403-404;
   "Truncated String Comparison Operators", p.405: "Unlike the DATA step, PROC
   SQL does not support the colon operators (such as =:, >:, and <=:) for
   truncated string comparisons. Use the alphabetic operators (such as EQT,
   GTT, and LET)."; same six with examples in Table 2.5, printed p.55-56).

   "Truncated" = the comparison is made over the length of the SHORTER
   operand (p.405: "truncating the longer string to be the same length as the
   shorter string"). This fixture pins each of EQT/NET/GTT/LTT/GET/LET against
   its DATA-step =:-family equivalent — both route through the ONE prefix
   compare (mkTruncCmp), so every pair below must list the SAME names — plus
   the shorter-operand rule (p.405's own example: 'TWOSTORY' eqt 'TWO' is
   true) and the zero-length rule ('' eqt '' is false — the shared helper's
   guard, Language Reference: Concepts p.130).

   Name-collision guard: GET/LET/NET are also plausible column names — the
   last block pins that a column named GET in operand position still resolves
   (only the infix word is an operator). */
data names;
  length name $8;
  input name $;
  datalines;
TWOSTORY
TWO
TWOFOLD
THREE
;
run;

data d_eq; set names; if name =:  'TWO'; run;
data d_ne; set names; if name ^=: 'TWO'; run;
data d_gt; set names; if name >:  'TH';  run;
data d_lt; set names; if name <:  'TW';  run;
data d_ge; set names; if name >=: 'TWO'; run;
data d_le; set names; if name <=: 'TW';  run;

title 'DATA step =: vs PROC SQL eqt';
proc print data=d_eq; run;
proc sql;
  select name from names where name eqt 'TWO';
quit;

title 'DATA step ^=: vs PROC SQL net';
proc print data=d_ne; run;
proc sql;
  select name from names where name net 'TWO';
quit;

title 'DATA step >: vs PROC SQL gtt';
proc print data=d_gt; run;
proc sql;
  select name from names where name gtt 'TH';
quit;

title 'DATA step <: vs PROC SQL ltt';
proc print data=d_lt; run;
proc sql;
  select name from names where name ltt 'TW';
quit;

title 'DATA step >=: vs PROC SQL get';
proc print data=d_ge; run;
proc sql;
  select name from names where name get 'TWO';
quit;

title 'DATA step <=: vs PROC SQL let';
proc print data=d_le; run;
proc sql;
  select name from names where name let 'TW';
quit;

title 'zero-length: eqt with empty literal keeps nothing';
proc sql;
  select name from names where name eqt '';
quit;

title 'a column named GET stays a column';
data g; input get x; datalines;
10 1
20 2
;
run;
proc sql;
  select get from g where get = 10;
  select get from g where x eqt 2;
quit;
