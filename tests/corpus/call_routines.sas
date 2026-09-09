/* QA regression: feasible CALL routines (dev2 8683a5f) — SORTN/SORTC/SCAN/
   CATS/CATT/CATX, value-verified vs SAS incl edge cases (missing sorts first,
   numeric auto-convert, negative scan index). CALL LABEL excluded (unstored labels). */
data _null_;
  length cs $ 20 ct $ 20 cx $ 20;
  a=3; b=1; c=2; call sortn(a, b, c);
  m1=8; m2=.; m3=4; call sortn(m1, m2, m3);
  p="cherry"; q="apple"; r="banana"; call sortc(p, q, r);
  call scan("hello world foo", 2, pos, len);
  call scan("a,b,c", -1, np, nl, ",");
  cs=""; call cats(cs, "a ", " b", "c");
  ct=""; call catt(ct, "a ", " b ", "c");
  call catx("|", cx, "x", 5, "z");
  put "sortn=" a b c;
  put "sortn_miss=" m1 m2 m3;
  put "sortc=" p q r;
  put "scan=" pos len;
  put "scan_neg=" np nl;
  put "cats=" cs;
  put "catt=" ct;
  put "catx=" cx;
run;
