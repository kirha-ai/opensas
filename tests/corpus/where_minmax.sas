/* GAP-whereminmax (doc-finder tick291 F5): the MIN/MAX infix WORD operators
   were deliberately excluded from WHERE expressions, though they worked in an
   assignment and in a subsetting IF. Language Reference: Concepts p.225: "Use the MIN or MAX
   operators to find the minimum or maximum value of two quantities…
   where x = (a min b);" (verbatim below) and p.215: "All SAS expression
   operators are valid for a WHERE expression, which include … minimum and
   maximum …". Only the SYMBOLS are WHERE-special: `<>` is NE and `><` errors
   (BUG-wherene, pinned in where_ch11_operators) — the word forms are ordinary
   Group-I operators on every route. */
data e; input a b; datalines;
1 2
3 1
;
run;
/* all four WHERE routes, the doc's p.225 shape (a min b) = 1 */
data r;  set e; where (a min b) = 1; put 'STMT ' a b; run;
data r2; set e(where=((a min b)=1)); put 'OPT  ' a b; run;
proc print data=e noobs; where (a min b)=1; run;
proc sql; select * from e where (a min b)=1; quit;
/* MAX word form, same four routes */
data r3; set e; where (a max b) = 2; put 'STMT-MAX ' a b; run;
data r4; set e(where=((a max b)=2)); put 'OPT-MAX  ' a b; run;
proc print data=e noobs; where (a max b)=2; run;
proc sql; select * from e where (a max b)=2; quit;
/* the ambiguity the exclusion guarded against: min/max as ordinary VARIABLE
   names in a WHERE must keep working on every route — operand position is
   untouched by the operator reading */
data v; input min max x; datalines;
5 9 1
1 2 8
4 7 3
;
run;
data r5; set v; where min > 3; put 'VAR-STMT ' min max x; run;
data r6; set v(where=(max < 8)); put 'VAR-OPT  ' min max x; run;
proc print data=v noobs; where min > 3; run;
proc sql; select * from v where min > 3; quit;
proc sql; select * from v where max < 8; quit;
/* a variable named min as the OPERAND of the word operator: min max x = max(min,x) */
data r7; set v; where (min max x) = 8; put 'VAR-INFIX ' min max x; run;
/* and as the right operand of a comparison: x = min (no row matches) */
data r8; set v; where x = min; put 'VAR-RHS ' min x; run;
