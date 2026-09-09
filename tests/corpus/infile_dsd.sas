data _null_;
  infile "tests/corpus/infile_dsd.dat" dsd firstobs=2;
  input name $ note : $9.;
  put "name=" name " note=" note;
run;
