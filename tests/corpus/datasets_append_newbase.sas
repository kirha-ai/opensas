/* BUG-datasetschange: APPEND to a non-existent BASE= auto-creates it as a
   copy of DATA= (SAS: append-to-nothing = create) instead of erroring — both
   PROC APPEND and PROC DATASETS APPEND; a second append to the now-existing
   base appends normally. CHANGE to a FREE name still renames. The ERROR paths
   (CHANGE to a taken name; MODIFY RENAME/FORMAT/LABEL of an unknown variable)
   fail loud and are pinned by proc.zig's captured-diag unit test — a step
   ERROR skips all later steps (BUG-errhalt), so they can't share a fixture. */
data src; id=1; x=10; run;
proc append base=fresh data=src; run;
proc print data=fresh noobs; run;
data more; id=2; x=20; run;
proc datasets lib=work nolist;
  append base=fresh2 data=more;
  append base=fresh2 data=more;
  change fresh=renamed;
quit;
proc print data=fresh2 noobs; run;
proc print data=renamed noobs; run;
