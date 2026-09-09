/* GAP-filenameref: a FILENAME-declared fileref resolves to its path for
   INFILE (and FILE) — previously FILENAME was inert and the bare fileref
   errored "expected an infile path". */
filename wordfile "tests/corpus/filename_infile.dat";
data words;
  infile wordfile;
  input w $;
run;
proc print data=words; run;
