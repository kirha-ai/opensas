/* BUG-datasetsdeletedisk: PROC DATASETS DELETE must unlink the ON-DISK member
   too — since the EXIST disk probe (84242c4), a memory-only delete left the
   member UNDEAD: exist()=1 after DELETE and a later SET resurrected the data.
   The member here is written mid-run via FILE (never loaded into memory), so
   DELETE exercises the pure disk path. */
libname L ".zig-cache";
data _null_;
  file ".zig-cache/dsdel_x.csv";
  put "v";
  put "42";
run;
data _null_;
  pre = exist('L.dsdel_x');
  put pre=;
run;
proc datasets lib=L nolist;
  delete dsdel_x;
quit;
data _null_;
  post = exist('L.dsdel_x');
  put post=;
run;
