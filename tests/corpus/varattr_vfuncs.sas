/* EXEC-varattr: FORMAT / INFORMAT / LABEL are stamped on the PDV var eagerly, so
   the V-attribute functions read them DURING the step (they previously saw only
   the BEST12./default until output). corpus-varattr. */
data _null_;
  amt = 1234.5;
  format amt comma10.2;
  informat amt comma8.;
  label  amt = "Amount Due";
  length nm $8;
  nm = "Ada";
  format nm $char8.;
  fx  = vformatx("amt");
  fnx = vformatnx("amt");
  fwx = vformatwx("amt");
  fdx = vformatdx("amt");
  val = vvaluex("amt");
  lbl = vlabelx("amt");
  cfx = vformatx("nm");
  put "FMT="     fx;
  put "FMTN="    fnx;
  put "FMTW="    fwx;
  put "FMTD="    fdx;
  put "VAL=["    val "]";
  put "LBL="     lbl;
  put "CHARFMT=" cfx;
run;
