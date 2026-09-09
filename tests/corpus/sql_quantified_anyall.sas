/* GAP-sqladvanced: quantified ANY/ALL subquery comparisons.
   x>ANY ⇔ x>min(S), x>=ALL ⇔ x>=max(S), =ANY ⇔ IN, <>ALL ⇔ NOT IN;
   empty set: ANY→false (0 rows), ALL→true (all rows). */
data a; input id x; datalines;
1 10
2 20
3 30
;
data b; input y; datalines;
15
25
;
data empty; input y; datalines;
;
proc sql;
  create table r1 as select id from a where x > any (select y from b);
  create table r2 as select id from a where x >= all (select y from b);
  create table r3 as select id from a where x = any (select y from b);
  create table r4 as select id from a where x <> all (select y from b);
  create table r5 as select id from a where x > any (select y from empty);
  create table r6 as select id from a where x <= all (select y from empty);
quit;
proc print data=r1 noobs; run;  /* expect 2, 3  */
proc print data=r2 noobs; run;  /* expect 3     */
proc print data=r3 noobs; run;  /* expect none  */
proc print data=r4 noobs; run;  /* expect 1,2,3 */
proc print data=r5 noobs; run;  /* expect none  */
proc print data=r6 noobs; run;  /* expect 1,2,3 */
