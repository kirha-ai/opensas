/* BUG-arraymultidimoor: for a MULTI-dimensional array, SAS 9.4 validates EACH
   per-dimension subscript against THAT dimension's bounds (and truncates it to an
   integer) BEFORE folding to the row-major flat index. Without the per-dim check,
   an out-of-range subscript that happens to fold to an in-range flat slot silently
   reads/writes the WRONG element with no error (data corruption). The ERROR is on
   stderr (asserted via captured diagnostics in exec.zig's test — the WRITE path);
   stdout here pins the runtime READ halt and that valid indexing + per-dimension
   truncation are unchanged.
   expect-rc: 1 */

data _null_;
  array a{2,2} a1-a4;
  a1=11; a2=12; a3=21; a4=22;
  put "valid=" a{2,2};      /* in-range: row 2, col 2 → a4 = 22 */
  put "trunc=" a{2.9,1};    /* each subscript truncated first: a{2,1} → a3 = 21 */
run;

data _null_;
  array a{2,2} a1-a4;
  a1=11; a2=12; a3=21; a4=22;
  i = 3;
  x = a{i,1};               /* row 3 does NOT exist → ERROR: subscript out of range */
  put "read-after=" x;      /* never reached — the step halted at the bad read */
run;

data _null_;
  put "skipped";            /* syntax-check mode after the ERROR (BUG-errhalt) */
run;
