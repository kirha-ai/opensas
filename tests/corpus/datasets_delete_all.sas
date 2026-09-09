/* BUG-datasetsdeleteall: PROC DATASETS DELETE _ALL_ removes EVERY WORK member
   (SAS 9.4), not a literal member named "_all_". Before the fix the lookup for
   "_all_" found nothing and silently succeeded, leaving stale datasets behind.
   Control: a single-member DELETE still drops only the one named table. */
data a; v = 1; run;
data b; v = 2; run;
data c; v = 3; run;
proc datasets library=work nolist;
  delete _all_;
run;
quit;
data _null_;
  e1 = exist("a"); e2 = exist("b"); e3 = exist("c");
  put "after_all=" e1 e2 e3;
run;

/* control — a named single-member DELETE removes only DROPME; KEEPME survives */
data dropme; v = 9; run;
data keepme; v = 7; run;
proc datasets library=work nolist;
  delete dropme;
run;
quit;
data _null_;
  d = exist("dropme"); k = exist("keepme");
  put "dropme=" d " keepme=" k;
run;
data show; set keepme; run;
proc print data=show; var v; run;
