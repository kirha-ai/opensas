/* BUG-sqlsumwgtcharzero — a CHARACTER argument to a numeric summary aggregate
   is an ERROR in SAS, not a 0 and not missing. Doc: SQL Procedure User's Guide,
   Table 2.6 (printed p.60; pdf 75 at offset +15, footer verified) defines
   SUMWGT as "sum of the WEIGHT variable values¹ … ¹ In the SQL procedure, each
   row has a weight of 1", and the summary-function Component (printed
   pp.411-413; pdf 426-428) defines the rest as statistical calculations over
   the column's values — weights and statistics are numbers, so a character
   argument has nothing to compute. 9bc08694's SUMWGT hoist made statAgg's
   empty-xs path unable to tell "no non-missing values" from "argument is not
   numeric at all": sumwgt(b) reported a computed 0 while n(b) counted 2 on the
   very same column. The guard sits in computeAgg / computeAggExpr — the one
   funnel every caller routes through — covers SUM/AVG + the whole isStatAgg
   set, and leaves COUNT/N/NMISS (type-agnostic), MIN/MAX (lexical on char),
   and the all-missing NUMERIC SUMWGT=0 (pinned below) untouched.
   NOTE: the last query ERRORS to stderr and prints nothing to stdout; the
   mutation check is that reverting the guard prints a `sw 0` table here and
   turns this golden red.
   expect-rc: 1 */

data d; length b $2 x 8; b='ab'; x=1; output; b='cd'; x=2; output; run;

/* numeric control on the SAME rows: the guard must not touch numerics */
proc sql; select n(x) as nn, sumwgt(x) as sw, sum(x) as s from d; quit;

/* all-missing numeric control: SUMWGT=0 while N=0 and SUM=. — the cell
   9bc08694 settled, pinned next to the char case so the two cannot drift */
data a; length x 8; x=.; output; x=.; output; run;
proc sql; select n(x) as nn, sumwgt(x) as sw, sum(x) as s from a; quit;

/* char-legal aggregates on the char column: the guard must not reach these */
proc sql; select n(b) as nn, nmiss(b) as nm, count(b) as c, min(b) as mn, max(b) as mx from d; quit;

/* the bug: character argument → loud ERROR, never a computed statistic */
proc sql; select sumwgt(b) as sw from d; quit;
