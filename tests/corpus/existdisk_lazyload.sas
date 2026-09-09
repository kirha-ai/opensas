/* BUG-existdisk (runtime half): a libref member whose name is built at RUN
   time (CALL SYMPUT) never appears as a literal lib.ds token in the setup
   pass, so the up-front preload misses it. The step loop must load it from
   disk when the runtime-expanded step finally names it. */
libname l "tests/programs/sas7bdat_read/inputs";
data _null_;
  call symput('ds', 'te');
run;
data _null_;
  set l.&ds;
  put etcd=;
run;
