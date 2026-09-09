/* Conditional numeric/char derivation with IFN and IFC */
data d; input v; datalines;
5
15
.
25
;
run;
data r;
  set d;
  length cat $4;
  flag = ifn(v > 10, 1, 0);
  cat  = ifc(v > 10, "HIGH", "LOW");
run;
proc print data=r; var v flag cat; run;
