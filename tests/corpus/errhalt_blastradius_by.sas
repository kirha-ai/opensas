/* SEV-errhaltblastradius (BY twin) — same pin through the pre-existing path:
   `proc print data=a; by x;` on UNSORTED input is a user error (rc 1), and
   every later step is SKIPPED — stdout is EMPTY. This suppression predates
   the rc epic (the `proc means by x` twin did the same at baseline, verified
   by probe), which is the justification for pinning the format twin's
   identical behavior in errhalt_blastradius.sas. A REGRESSION looks like:
   stdout gains the `b` table or the rc moves off 1; the clean-direction
   control is errhalt_blastradius_control. expect-rc: 1 */
data a; x=2; y=1; run;
data a2; x=1; y=2; run;
data a; set a a2; run;
proc print data=a; by x; run;
data b; set a; m = y + 1; run;
proc print data=b; run;
