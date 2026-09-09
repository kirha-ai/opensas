/* BUG-informatwidth: a char var created by an INFORMAT statement takes the
   informat WIDTH as its declared length (Language Reference: Concepts p.72), so PROC CONTENTS and an
   OUT= dataset carry Char 12 — not the widest stored value. x: numeric 8.2
   informat → INFORML=8 INFORMD=2, Len stays 8. y: $12. → Len 12, INFORML=12.
   f: FORMAT-created char is unchanged (Len 8 from its $char8. format). */
data d;
  informat x 8.2 y $12.;
  format f $char8.;
  x = 1.23;
  y = "abc";
  f = "hi";
run;
proc contents data=d out=meta; run;
proc print data=meta noobs;
  var name type length informat informl informd format formatl formatd;
run;
