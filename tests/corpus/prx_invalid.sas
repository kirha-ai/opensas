/* doc-finder tick133 (GAP-prxinvalidnote): an invalid PRX pattern must fail
   LOUD — SAS writes an ERROR to the log and PRXPARSE returns missing. opensas
   now prints the ERROR to stderr (the SAS-style log); stdout pins the missing
   value. (The loud ERROR itself is asserted via captured diagnostics in
   src/prx.zig tests.) */
data _null_;
  rx = prxparse('/(abc/');   /* unbalanced '(' -> ERROR on stderr, rx=. */
  put "rx=" rx;
run;
