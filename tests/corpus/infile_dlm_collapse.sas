/* BUG-dlmcollapse: NON-DSD list input collapses a RUN of consecutive delimiters
   into ONE separator (SAS 9.4). `dlm=','` on `one,,two,,three` reads three fields
   one/two/three (the empty stretches between commas are NOT missing values).
   Contrast DSD: consecutive delimiters DO delimit empty/missing fields, so the
   same record reads one/(missing)/two/(missing)/three. Locks the distinction. */
data nodsd;
  infile datalines dlm=',';
  input x $ y $ z $;
datalines;
one,,two,,three
;
run;
proc print data=nodsd noobs; run;

/* DSD: consecutive delimiters = missing fields (collapse must NOT apply). */
data dsd;
  infile datalines dsd dlm=',';
  input a $ b $ c $ d $ e $;
datalines;
one,,two,,three
;
run;
proc print data=dsd noobs; run;
