/* BUG-procwherestmtsilent: a PROC-level WHERE whose predicate FAILS TO PARSE
   used to be dropped silently along with its diagnostics — the proc then ran
   on the FULL (unfiltered) table and exited 0. SAS 9.4 fails the step. The
   parse error must propagate LOUD and ABORT the proc (no full-table output).
   The valid PROC PRINT below still filters to id>=2; the malformed WHERE proc
   prints NOTHING to stdout and reports an ERROR to stderr (exit 1). If the
   silent swallow regresses, the 2nd proc would summarize ALL rows here and
   mismatch.
   expect-rc: 1 */
data d; input id v; datalines;
1 10
2 20
3 30
;
run;
proc print data=d noobs;
  where id >= 2;
  var id v;
run;
proc means data=d;
  where v > ;
run;
