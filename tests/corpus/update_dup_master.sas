/* ORACLE-unblocked-batch item 5 (NOTE-updatedupmaster) — UPDATE with DUPLICATE
   BY keys in the MASTER data set. Pinned CONFORMANT against three sentences of
   SAS 9.4 DATA Step Statements: Reference, all verified against the page
   markers, not copied from a board line:

     printed p.352 (marker "=== pdf 363 ===", footer "352 Chapter 2 / ..."):
       "Each observation in the master data set should have a unique value of
        the BY variable or BY variables. If there are multiple values for the
        BY variable, only the first observation with that value is updated.
        The transaction data set can contain more than one observation with the
        same BY value. (Multiple transaction observations are all applied to
        the master observation before it is written to the output file.)"

     printed p.353 (marker "=== pdf 364 ===", footer "UPDATE Statement 353"):
       "The output data set contains one observation for each observation in
        the master data set."

   So all three of these are pinned here at once:
     - 5 master obs in  ->  5 obs out (one per MASTER obs, not per BY group);
     - only the FIRST id=2 obs is updated; the 2nd and 3rd keep 'c' and 'd';
     - BOTH id=2 transactions (Y then Z) land on that first obs, so it is 'Z'
       and not 'Y' — the parenthesised sentence above.

   Real SAS also logs "The MASTER data set contains more than one observation
   for a BY group." for each extra id=2 master row, and sets _ERROR_=1 on those
   rows (NOTE-updatedupmaster). This fixture pins the DATA; the executor test
   pins the captured warnings and _ERROR_ flags. */
data master;
  input id v $;
datalines;
1 a
2 b
2 c
2 d
3 e
;
run;
data trans;
  input id v $;
datalines;
2 Y
2 Z
;
run;
data out;
  update master trans;
  by id;
run;
proc print data=out; run;
