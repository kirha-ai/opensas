/* BUG-dsobsvaluenovalidate (doc-finder tick300 F5): the dataset-option path
   validated option NAMES (BUG-wheredsoptswallow) but never option VALUES —
   `set d(obs=abc)` silently read EVERY row while the OPTIONS-statement and
   INFILE-option paths both error on the same garbage. Garbage values now fail
   LOUD naming the option and the value (pinned by in-file tests in io.zig);
   this green fixture pins the documented values that ARE honoured. */

data five; do i=1 to 5; output; end; run;

/* obs=2k is 2048 (the K suffix used to silently misparse to 2) → all 5 rows */
data a; set five(obs=2k); run;
proc print data=a noobs; run;

/* firstobs=max starts at the LAST observation (was: silently all 5 rows) */
data b; set five(firstobs=max); run;
proc print data=b noobs; run;

/* obs=min is 1 */
data c; set five(obs=min); run;
proc print data=c noobs; run;

/* ordinary ranges unchanged: an upper bound, not a count */
data d; set five(firstobs=2 obs=4); run;
proc print data=d noobs; run;
