/* QA tick284 OVER-STRICT lock for BUG-transposeoptswallow (471645f): PROC
   TRANSPOSE now ERRORs on an unknown header option / sub-statement, and a false
   ERROR is expensive — syntax-check mode (BUG-errhalt) then skips EVERY later
   step of the program. This fixture is the positive control: every option and
   statement below is VALID SAS 9.4 TRANSPOSE syntax and must keep running.
   (Two forms were known-broken by that landing and were absent here: a
   mid-step TITLE/FOOTNOTE/OPTIONS and a QUOTED prefix=/name= value — fixed
   by BUG-transposeglobalstmt / BUG-transposeoptquoted, both included below.) */
proc format; value grpf 1='Alpha' 2='Beta'; run;

data src; input grp $ k v w; format k grpf.; datalines;
G1 1 10 1
G1 2 20 2
G2 1 30 3
G2 2 40 4
;
run;

/* every header option: prefix= suffix= name= label= delimiter= let, and data=
   dataset options routed through the shared input pipeline */
proc transpose data=src(where=(v>10) keep=grp k v) out=o1 prefix=P suffix=_S name=_n_ label=_l_ delimiter=Z let;
  id k;
  var v;
run;
proc print data=o1; run;

/* ID (formatted) + BY + COPY + IDLABEL + a LABEL statement + a WHERE statement,
   with a numbered VAR range and out= dataset options */
proc transpose data=src out=o2(rename=(_NAME_=which));
  where k >= 1;
  by grp;
  id k;
  idlabel k;
  copy w;
  label v='ignored';
  var v-w;
run;
proc print data=o2; run;

/* obs=/firstobs=/rename= on the input, quoted delimiter/suffix/label values */
proc transpose data=src(firstobs=2 obs=3 rename=(v=vv)) out=o3 delimiter='-' suffix="_x";
  id grp k;
  var vv;
run;
proc print data=o3; run;

/* F1 (BUG-transposeglobalstmt): a mid-step TITLE/FOOTNOTE/OPTIONS is legal SAS
   inside a PROC — main.zig hoists it and leaves the tokens in the step, which
   TRANSPOSE must skip, never ERROR on (the ERROR killed every later step via
   BUG-errhalt). The trailing PRINT proves the program keeps running. */
proc transpose data=src out=o4;
  title "mid-step global";
  footnote "mid-step foot";
  options nodate;
  var v;
run;
proc print data=o4; run;

/* F4 (BUG-transposeoptquoted): a QUOTED prefix=/name= value must be accepted,
   consistent with suffix=/label=/delimiter= which always took quotes
   (DELIMITER=<'>delim<'> is documented quotable in SAS 9.4; whether SAS itself
   quotes PREFIX= is needs-oracle — the five options behave the same either
   way). The title/footnote from the previous step persist, as SAS does. */
proc transpose data=src out=o5 prefix="Q" name='_src_';
  var v w;
run;
proc print data=o5; run;
