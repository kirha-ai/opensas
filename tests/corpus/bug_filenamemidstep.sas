/* BUG-filenamemidstep (QA tick336 F1 — the fourth live D-014a violation):
   the DATA-step parser's global-statement skip arm (atGlobalStmt) claimed the
   wide isGlobalKw while the top level only HANDLED hoisted ∪ pre-pass ∪ inert
   statements mid-step — a mid-DATA-step `filename f 'new';` was swallowed
   UN-EXECUTED, so `file f;` kept writing to the OLD path at exit 0 with zero
   diagnostics (SILENT WRONG DATA). FILENAME/ODS now join the main.segments
   hoist (SAS: a global statement takes effect when ENCOUNTERED — during step
   compilation, before the step executes), and atGlobalStmt skips exactly the
   converged parser.isMidStepSkippable.
   FIXED CASE: the mid-step FILENAME re-binds fmid BEFORE the step runs, so
   WROTE-HERE lands in the NEW file (the read-back below ERRORs "Physical file
   does not exist" on an unfixed binary — this fixture is red without the fix;
   fmid_old.txt must never be created).
   POSITIVE CONTROLS: mid-DATA title/page, and mid-PROC filename + ods
   destination (an accepted listing no-op) keep working — and the mid-PROC
   FILENAME binding is real: a later step writes through it. */
filename fmid "tests/corpus/includes/fmid_old.txt";
data _null_;
  x = 1;
  filename fmid "tests/corpus/includes/fmid_new.txt";
  file fmid;
  put 'WROTE-HERE';
run;
data _null_;
  infile "tests/corpus/includes/fmid_new.txt" truncover;
  input s $20.;
  put "NEW file contains: [" s "]";
run;

data _null_;
  title 'midstep-ctl';
  page;
  x = 2;
  put "ctl ran, x=" x;
run;

data ctl;
  input v;
datalines;
7
;
run;
proc print data=ctl noobs;
  filename fmid2 "tests/corpus/includes/fmid2.txt";
  ods listing;
  var v;
run;
data _null_;
  file fmid2;
  put 'VIA-MIDPROC-BIND';
run;
data _null_;
  infile "tests/corpus/includes/fmid2.txt" truncover;
  input s $20.;
  put "MIDPROC bind contains: [" s "]";
run;
