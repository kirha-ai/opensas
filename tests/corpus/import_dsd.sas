/* GREEN lock (doc-finder tick223): DBMS=CSV DSD parsing is correct —
   quoted embedded comma, "" escaped quote, empty field = missing, and a
   clean numeric column is typed numeric. The tick223 pin that a zero-padded
   code (007) stays CHARACTER is OVERTURNED by live SAS 9.4 (GH#29,
   BUG-importleadingzero, D-026): EFI types it NUMERIC (informat best32.),
   so 007 prints 7. */
proc import out=t datafile="tests/corpus/includes/import_dsd.csv" dbms=csv replace;
  getnames=yes;
run;
proc print data=t noobs; run;
