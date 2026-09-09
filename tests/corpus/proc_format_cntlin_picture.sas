/* CNTLIN= rebuild of a PICTURE format (TYPE='P') and of SEXCL/EEXCL exclusive
   endpoints (BUG-cntlinpicture).
   (a) A CNTLOUT row with TYPE='P' must rebuild a PICTURE format — the label is a
       digit template, not a literal: put(x, ppx.) renders `  31.4`, never the raw
       template `0009.9`. FMTNAME is renamed only to dodge first-match shadowing
       by the directly-defined original in the same run (catalog is append-only).
   (b) SEXCL/EEXCL='Y' rebuild an EXCLUSIVE endpoint (direct `0-<5` twin), so the
       shared boundary 5 maps to the NEXT range — an inclusive rebuild maps it low. */
proc format cntlout=ctl;
  picture ppict low-high='0009.9';
run;
data ctl;
  set ctl;
  fmtname = "ppx";
run;
proc format cntlin=ctl; run;
data ctl2;
  length fmtname $8 start end $8 label $8 type $1 hlo $1 sexcl eexcl $1;
  fmtname="EXF"; start="0";  end="5";  label="low";  type=""; hlo="";  sexcl="N"; eexcl="Y"; output;
  fmtname="EXF"; start="5";  end="10"; label="mid";  type=""; hlo="";  sexcl="N"; eexcl="Y"; output;
  fmtname="EXF"; start="10"; end="";   label="high"; type=""; hlo="H"; sexcl="N"; eexcl="N"; output;
run;
proc format cntlin=ctl2; run;
data _null_;
  x = 31.4;
  put x ppict.;  /* directly-defined picture: unchanged */
  put x ppx.;    /* CNTLOUT->CNTLIN round-trip: identical render */
  do x = 4.999, 5, 9.999, 10;
    put x exf.;  /* low, mid (boundary 5 -> next range), mid, high */
  end;
run;
