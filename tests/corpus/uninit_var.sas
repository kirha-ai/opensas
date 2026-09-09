/* GH#75 ISS-uninitvar: a variable read on a RHS but never assigned / INPUT /
   retained / SET/MERGE'd is uninitialized — SAS logs
   `NOTE: Variable ghost is uninitialized.` ONCE per step (goes to stderr, not
   this stdout diff; the in-file test block pins the once-per-var NOTE).

   ghost   -> read twice, never set   => uninitialized (one NOTE), reads missing
   acc     -> retained + assigned      => NOT uninitialized
   src var seen -> from SET            => NOT uninitialized
   Here we pin the resulting values so a silent-drop regression shows up. */
data SRC; seen = 7; output; run;
data _null_;
  set SRC;
  retain acc 0;
  acc = acc + 1;
  y = ghost + 1;   /* ghost uninitialized -> missing -> y missing */
  z = ghost * 2;   /* second read: still one NOTE (dedup) */
  put "acc=" acc " y=" y " z=" z " seen=" seen;
run;
