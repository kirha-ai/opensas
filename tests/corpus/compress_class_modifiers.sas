/* COMPRESS class modifiers route through the shared class machinery
   (classMod/matchesClass): keep-mode k with n/l/u and remove-mode with
   a/d/p/s. Regression guard for BUG-compressclass (silent drop of every
   class modifier beyond a/d/p/s). Unknown modifier errors loudly (D-002);
   the bad row prints missing — and since COMPRESS is a CHARACTER function that
   missing is a BLANK CHARACTER, not the numeric `.` this golden used to show
   (BUG-scanmissingtype). The vtype line below pins the type, so the assertion
   is STRONGER than the `bad=.` it replaces, not weaker.
   expect-rc: 1 */
data _null_;
  kn = compress('a b!c@d',,'kn');
  kl = compress('AbCdEf',,'kl');
  ku = compress('AbCdEf',,'ku');
  kd = compress('a1b2c3',,'kd');
  ka = compress('Ab c9!',,'ka');
  kf = compress('9a_b!',,'kf');
  rp = compress('a,b!c.',,'p');
  rs = compress('a b c',,'s');
  rd = compress('a1b2',,'d');
  put "kn=" kn / "kl=" kl / "ku=" ku / "kd=" kd / "ka=" ka / "kf=" kf
      / "rp=" rp / "rs=" rs / "rd=" rd;
run;

/* unknown modifier letter errors loudly (stderr ERROR, non-zero exit) and
   yields missing — never silently ignored (D-002). */
data _null_;
  bad = compress('abc',,'kz');
  badt = vtype(bad);
  put "bad=" bad;
  put "badtype=" badt;
run;
