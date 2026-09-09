/* QA tick322 F4 / BUG-libnamemidstepboth — a mid-PROC-step LIBNAME is EXECUTED
   by the up-front parseLibnames pre-pass (a whole-program scan that binds the
   libref and preloads its datasets before step 1 runs), so the PROC statement
   loop must SKIP its leftover tokens, not fail loud on them (D-014a: skip ==
   handled). Pre-fix it BOTH ran AND errored (exit 2, listing lost). FILENAME/
   ODS mid-PROC were loud then (no pre-pass, not yet hoisted); since
   BUG-filenamemidstep they are HOISTED and EXECUTED like TITLE/OPTIONS —
   pinned by the main.zig unit test (this fixture is the green path: stdout
   at exit 0). */
data d; x=1; run;

proc print data=d noobs;
  libname L ".zig-cache";
  var x;
run;

/* positive control: hoisted + inert mid-step statements keep working */
proc print data=d noobs;
  title 'ctl';
  page;
  var x;
run;
