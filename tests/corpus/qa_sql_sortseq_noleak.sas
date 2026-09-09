/* QA tick417 cross-landing sweep — SQL's SORTSEQ=LINGUISTIC comparator must not
   leak past ORDER BY, checked on SIX paths the landing (f6fdd6de) did not probe.

   GAP-sqlsortseqlinguistic forked PROC SQL's comparator into cmpVal (byte) and
   cmpValColl (case-folded), with only orderRows passing ling=true. That split
   exists because of SQL Procedure User's Guide printed p.45 (`=== pdf 60 ===`):
   "Note: SORTSEQ= affects only the ORDER BY clause. It does not override your
   operating environment's default comparison operations for the WHERE clause."
   Its own fixture (sql_sortseq_scope.sas) pins WHERE, DISTINCT and GROUP BY.
   This one pins the paths nobody checked, all of which route through cmpVal:

     UNION            set operations must not merge apple with APPLE
     subquery IN      a folded match would pull APPLE into an apple filter
     self-join =      an equijoin on a char key must stay byte-exact
     MIN / MAX        lexical aggregates, not ordering
     HAVING           char predicate on a grouped column
     INTO :           takes the COLLATED order, because it reads ORDER BY —
                      the one place the collation SHOULD reach

   apple and APPLE are the probe: EQUAL under the fold, DISTINCT under bytes, so
   any leak collapses rows or over-matches rather than merely reordering. A leak
   that merges them destroys a row, which is why this is pinned rather than
   argued. Verified base-vs-head over both binaries in the tick417 differential:
   only the INTO: line moved, and it moved in the correct direction.
   expect-rc: 0 */
data t;
  input name $ v @@;
datalines;
Zebra 1 apple 2 Banana 3 apple 4 APPLE 5
;
run;

options sortseq=linguistic;

title "UNION keeps apple and APPLE as separate rows";
proc sql;
  select name from t union select name from t;
quit;

title "subquery IN stays byte-exact: only the two lowercase apple rows";
proc sql;
  select name, v from t where name in (select name from t where v = 2) order by v;
quit;

title "self-join on a char key stays byte-exact";
proc sql;
  select count(*) as n from t a, t b where a.name = b.name;
quit;

title "MIN/MAX are lexical, not collated";
proc sql;
  select min(name) as lo, max(name) as hi from t;
quit;

title "HAVING on a char group stays byte-exact: apple only, count 2";
proc sql;
  select name, count(*) as n from t group by name having name = 'apple';
quit;

title "INTO: DOES take the collated ORDER BY order - the one path it must reach";
proc sql noprint;
  select name into :lst separated by ',' from t order by name;
quit;
%put INTO_LIST=&lst;
