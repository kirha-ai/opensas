/* BUG-coloninformatwidth: a colon-modified informat `:$w.` sets the variable's
   storage length to w AND truncates the read to w characters — the informat
   width governs the read, not just the token length. Control: a bare `$` (plain
   list input, no informat) keeps SAS's default 8-char length (BUG-inputlistlen). */
data t;
  input full : $20. trunc : $10. dflt $;
  datalines;
Christopher Abcdefghijklmnop Nathaniel
Bob Xy Al
;
run;
proc print data=t noobs; run;
proc contents data=t; run;
