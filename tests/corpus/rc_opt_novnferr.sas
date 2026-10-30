/* GAP-opt-unknown-sweep: NOVNFERR is the documented behavior-changing half of
   VNFERR/NOVNFERR. opensas still errors on unknown variable names, so silently
   accepting NOVNFERR would leave the opposite behavior under a safety-relevant
   option. D-018 keeps this out of the rc-1 typo arm and marks it as a gap.
   expect-rc: 2 */
data before;
  x = 1;
run;
proc print data=before noobs;
run;
options novnferr;
