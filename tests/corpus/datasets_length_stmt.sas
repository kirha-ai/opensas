/* BUG-datasetslengthstmtnoop: the MODIFY-level `length` STATEMENT was a
   SILENT no-op ("parsed but a no-op (char width not tracked here)") while
   the sibling ATTRIB LENGTH= arm failed loud (2724b755) — the same user
   intent loud one way and silent the other (D-002). Real SAS REJECTS the
   statement here: Base SAS 9.4 Procedures Guide 7th ed. printed p.563
   (DATASETS restrictions): "You cannot change the length of a variable
   using the LENGTH statement or the LENGTH= option in an ATTRIB
   statement", and LENGTH is absent from MODIFY's p.576
   subordinate-statement syntax diagram. rc 1, not 2 — the user's SAS is
   wrong, the ATTRIB arm's own verdict (D-009 / D-009b corollary).
   expect-rc: 1 */
data m;
  length c $8;
  c = "x";
run;
proc datasets lib=work nolist;
  modify m;
  length c $20;
quit;
