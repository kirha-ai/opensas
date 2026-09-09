/* NOTE-declarehashtrim (QA tick336 F8): "the `dataset:` name TRIM landed on
   `h.output()` but not on `declare hash`, so the two ends of the same feature
   disagree." REPRODUCED (declare end errored 'hash dataset woo       not
   found' for an EXISTING member — loud but wrong), then FIXED in exec.zig's
   hashDeclare with the same trim hashOutput grew in BUG-hashoutputnametrim.
   This fixture pins the split-by-group idiom working at BOTH ends; the
   captured-diagnostics test in src/exec.zig (NOTE-declarehashtrim) pins it
   in isolation. */
data woo; input x; datalines;
1
;
run;
data _null_;
  if 0 then set woo;
  length nm $8;
  nm = 'oo';
  declare hash h(dataset: 'w' || nm);
  h.defineKey('x');
  h.defineData('x');
  h.defineDone();
  rc = h.find(key: 1);
  put rc= x=;
  declare hash o();
  o.defineKey('x');
  o.defineData('x');
  o.defineDone();
  rc = o.add(key: 1, data: 1);
  length nm2 $8;
  nm2 = 'ooout';
  rc = o.output(dataset: 'w' || nm2);
run;
data _null_;
  set wooout;
  put x=;
run;
