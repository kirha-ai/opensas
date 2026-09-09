/* BUG-vformatxlabel: VFORMATX/VLABELX/VVALUEX must return the ASSIGNED format/
   label — including when it lives on a SET source's column, not the fresh PDV. */
data d;
  amt = 1234.5;
  format amt dollar10.2;
  label amt = "The Amount";
run;
data _null_;
  set d;
  length fmt lbl val $20;
  fmt = vformatx("amt");
  lbl = vlabelx("amt");
  val = vvaluex("amt");
  put "fmt=[" fmt "]";
  put "lbl=[" lbl "]";
  put "val=[" val "]";
run;
data _null_;
  z = 42;
  format z comma8.2;
  label z = "Zed";
  length zf zl $20;
  zf = vformatx("z");
  zl = vlabelx("z");
  put "in_fmt=[" zf "]";
  put "in_lbl=[" zl "]";
run;
