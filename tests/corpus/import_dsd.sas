/* GREEN lock (doc-finder tick223): DBMS=CSV DSD parsing is correct —
   quoted embedded comma, "" escaped quote, empty field = missing, and a
   zero-padded code (007) stays character while a clean numeric column is
   typed numeric. */
proc import out=t datafile="tests/corpus/includes/import_dsd.csv" dbms=csv replace;
  getnames=yes;
run;
proc print data=t noobs; run;
