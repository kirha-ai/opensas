/* GAP-gapsexitingone §5d — the typo arm of the FILENAME-device SPLIT:
   `bogusdev` is in NO documented device list, so this is the user's SAS
   being wrong → rc 1 ("fix your SAS") with the "not recognized" wording —
   never the gap arm's "not supported" at rc 2. Twin of rc_filename_pipe.sas.
   expect-rc: 1 */
data a;
  x = 1;
run;
proc print data=a;
run;
filename f bogusdev "x";
