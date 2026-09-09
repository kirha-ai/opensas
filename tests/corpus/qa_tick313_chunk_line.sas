/* NOTE-chunkrelativelineno (QA tick312 F3): a diagnostic after the first
   top-level run; reports the ABSOLUTE source line — zzzq below is line 11
   (was chunk-relative L3). main.zig's unit test pins the number; this
   fixture pins that the steps before the error still print.
   expect-rc: 1 */
data d;
  x=1;
  y=2;
run;
proc print data=d noobs;
run;
zzzq 5;
