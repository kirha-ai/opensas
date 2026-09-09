/* BUG-infileput: `put _infile_;` / `put _infile_=;` — _INFILE_ referenced ONLY
   in a PUT statement. Was: uninitScanStmt's .put case dropped .variable/.named
   items, so refs_infile was never set, the raw record was never published, and
   PUT rendered `.`. Must print the raw current input record. */
data _null_;
  input x $;
  put _infile_;
  put _infile_=;
datalines;
hello raw
second line
;
run;
