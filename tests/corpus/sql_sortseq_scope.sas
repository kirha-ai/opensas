/* GAP-sqlsortseqlinguistic, the RESTRICTION half — SORTSEQ= must change ORDER
   BY and NOTHING ELSE. SQL Procedure User's Guide printed p.45
   (`=== pdf 60 ===`): "Note: SORTSEQ= affects only the ORDER BY clause. It does
   not override your operating environment's default comparison operations for
   the WHERE clause."

   That is why the collation is threaded through a SEPARATE `cmpValColl` that
   only `orderRows` calls with ling=true, rather than folded into `cmpVal`
   itself — folding `cmpVal` would have been the one-word change and it would
   have silently broken WHERE, DISTINCT, GROUP BY and UNION at the same time.
   Data deliberately contains apple/APPLE, which are EQUAL under the collation
   and DISTINCT under every comparison, so each half fails loudly if crossed:

     * WHERE name = "apple" must match the two lowercase rows only. This one
       asserts the guarantee rather than guarding the change: WHERE compares
       through eval.zig, never through cmpVal, so a cmpVal leak cannot reach it
       (verified by mutation — folding cmpVal left this block green). The two
       blocks below are the load-bearing ones.
     * SELECT DISTINCT must keep apple and APPLE as SEPARATE rows (4 of them).
       If the collation leaked into grouping they would collapse to 3 — a row
       silently destroyed, the worst class.
     * GROUP BY must count them separately (APPLE=1, apple=2). A leak shows as
       a single apple=3 bucket.
     * ORDER BY, and only ORDER BY, sorts them adjacently.

   The tie between apple and APPLE is also why `orderRows` had to move from
   std.mem.sort (pdq, UNSTABLE) to std.sort.block (stable): case-folding
   MANUFACTURES ties that a byte compare never produces, so without stability
   their relative order would be nondeterministic at real-data sizes. This
   fixture pins that order too — first-seen input order, apple before APPLE.
   expect-rc: 0 */
data t;
  input name $ @@;
datalines;
Zebra apple Banana apple APPLE
;
run;

options sortseq=linguistic;

title "WHERE stays byte-exact: two lowercase apple rows, no APPLE";
proc sql;
  select name from t where name = "apple";
quit;

title "DISTINCT stays byte-exact: 4 rows, apple and APPLE both present";
proc sql;
  select distinct name from t order by name;
quit;

title "GROUP BY stays byte-exact: APPLE 1, apple 2, Banana 1, Zebra 1";
proc sql;
  select name, count(*) as n from t group by name order by name;
quit;
