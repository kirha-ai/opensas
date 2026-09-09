/* GAP-procopts (tick330 EBNF audit, proc_opts): the PROC statement-option
   surface converged on fail-loud for unknown options (D-002) — an unknown
   option was LOUD on PROC PRINT but SILENTLY SKIPPED on PROC MEANS (and RANK,
   DELETE, DATASETS, EXPORT, IMPORT had their own silent `else i += 1`s).
   This fixture is the POSITIVE CONTROL, the important half: a pile of
   honoured and legitimately-inert options across every touched PROC must
   keep parsing and rendering at exit 0. The loud arms (bogusopt=, maxddec=,
   grups=, kll, memtype=catalog, putname/getname typos) are pinned by the
   captured-diagnostics test in src/proc.zig — never a real aborting process. */
data d;
  input g $ x;
  datalines;
a 1
a 2
b 3
b 4
;
run;
/* MEANS: honoured name=value (maxdec= alpha= order= vardef=) + honoured flags
   (nway missing descending) + inert tuning (sumsize= threads) + stat keywords */
proc means data=d maxdec=2 alpha=0.1 order=freq vardef=n n mean std clm nway missing descending sumsize=1000 threads;
  class g;
  var x;
run;
/* SUMMARY shares the MEANS header parser — same surface, silent by default */
proc summary data=d nway print;
  class g;
  var x;
  output out=s mean=m;
run;
proc print data=s noobs;
run;
/* RANK: ties= descending + the out=r(keep=…) dataset-option paren group */
proc rank data=d out=r(keep=x rx) ties=low descending;
  var x;
  ranks rx;
run;
proc print data=r noobs;
run;
/* DATASETS: nolist / nodetails / memtype=data are the directory-listing knobs
   — inert here, no directory listing is ever printed; the delete still runs */
proc datasets lib=work nolist nodetails memtype=data;
  delete r;
run;
quit;
proc print data=s noobs;
run;
