/* GAP-gapsexitingone §5b re-verdict — LABEL is a valid-in-MEANS statement
   (Procedures Guide, 7th ed., Syntax Tip printed p. 1481: 'You can use the
   ATTRIB, FORMAT, LABEL, and WHERE statements') opensas does not implement —
   an opensas gap, exit 2. Typo twin: rc_means_stmt_typo.sas. expect-rc: 2 */
data h;
  input x;
  datalines;
1
;
run;
proc means data=h;
  var x;
  label x='a';
run;
