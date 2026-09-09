/* SEV-rcbydesignerr: a duplicate:'e' condition is rc-by-design — the program
   checks the rc and handles it (Component Objects Ref: ADD's rc contract
   printed p.24, duplicate:'e' printed p.32). The ERROR must still be logged
   (and the exit code stays non-zero), but it must NOT errhalt-skip LATER
   steps — the D-014 shape. This .txt pins the STDOUT side: every step after
   the handled condition still runs. The ERRORs themselves go to stderr and
   are pinned by the captured-reporter test in exec.zig.
   expect-rc: 1 */
data src; input k d; datalines;
1 10
1 20
2 30
;
run;
data _null_;
  declare hash h(dataset:'src', duplicate:'e');
  h.defineKey('k'); h.defineData('k','d'); h.defineDone();
  put 'LOADED first-wins';
run;
data _null_;
  declare hash h2(duplicate:'e');
  rc = h2.defineKey('k'); rc = h2.defineData('d'); rc = h2.defineDone();
  k = 1; d = 10; rc = h2.add();
  rc = h2.add();
  if rc = 1 then put 'ADD DUP HANDLED rc=1';
run;
data later;
  x = 42;
  put 'LATER STEP RAN x=' x;
run;
proc print data=later; run;
