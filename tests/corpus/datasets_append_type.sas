/* BUG-datasetsappendtype: PROC DATASETS APPEND type-checks + FORCE-gates like
   PROC APPEND (SAS 9.4). A matching-type append works. A char->num mismatch
   without FORCE ERRORs and appends nothing — the old dsAppend copied columns
   by name and silently landed 'oops' in numeric x. The mismatch step runs
   LAST: after a step ERROR later steps are skipped (BUG-errhalt), so this
   fixture's stdout pins the pre-ERROR state; proc.zig's unit test pins base
   unchanged + the captured ERROR. FORCE coverage is in the unit test too.
   expect-rc: 1 */
data base; x=1; run;
data good; x=2; run;
proc datasets lib=work nolist; append base=base data=good; quit;
proc print data=base noobs; run;
data bad; length x $5; x='oops'; run;
proc datasets lib=work nolist; append base=base data=bad; quit;
