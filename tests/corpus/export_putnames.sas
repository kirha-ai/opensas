/* BUG-exportputnames: PROC EXPORT must honor PUTNAMES=NO — the exported file
   carries NO header row (data rows only); PUTNAMES=YES and the default keep it.
   The option used to be dropped silently → a NO file wrongly carried the header.
   Read the RAW files back (a PROC IMPORT round-trip would hide the bug). (no PHI) */
data d;
  x=1; y=2; output;
run;
proc export data=d outfile="tests/corpus/includes/pn_no.csv" dbms=csv replace;
  putnames=no;
run;
proc export data=d outfile="tests/corpus/includes/pn_yes.csv" dbms=csv replace;
run;
data no_hdr;
  infile "tests/corpus/includes/pn_no.csv" truncover;
  length line $32;
  input line $;
run;
proc print data=no_hdr noobs; run;
data with_hdr;
  infile "tests/corpus/includes/pn_yes.csv" truncover;
  length line $32;
  input line $;
run;
proc print data=with_hdr noobs; run;
