/* GAP-gapsexitingone §5d — FILENAME's PIPE device is in the syntax diagram's
   closed device list (valid SAS 9.4; opensas has DISK only), so the refusal
   is a gap → rc 2. The SPLIT keeps a typo'd device word (rc_filename_
   baddevice.sas) at rc 1 on the same guard.
   expect-rc: 2 */
data a;
  x = 1;
run;
proc print data=a;
run;
filename cmd pipe "echo hi";
