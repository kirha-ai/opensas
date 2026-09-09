/* BUG-coloninformatat: a colon-modified informat (`:$w.`) after an explicit `@n`
   column pointer stays LIST-style — `@n` sets the START column, then the read
   scans from there to the next delimiter, truncating to w. It must NOT revert to
   a fixed-width w-column grab. Control `ctrl`: an `@n` WITHOUT a colon still takes
   the full fixed-width columns (embedded blanks included) — unchanged. */
data t;
  input @1 a : $20. @3 b : $10. @1 ctrl $8.;
  datalines;
Hi There friend
XXHello World now
;
run;
proc print data=t noobs; run;
