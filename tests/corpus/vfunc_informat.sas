/* V-attribute functions read a variable's INFORMAT — both the by-reference (non-X)
   and the name-string (X) forms. Unblocked by EXEC-varattr. corpus-vfuncs. */
data _null_;
  amt = 5;
  informat amt comma8.;
  length nm $8; nm = "x";
  informat nm $char8.;
  i  = vinformat(amt);
  in = vinformatn(amt);
  iw = vinformatw(amt);
  id = vinformatd(amt);
  ix = vinformatx("amt");
  ci = vinformat(nm);
  put "VINFORMAT="  i;
  put "VINFORMATN=" in;
  put "VINFORMATW=" iw;
  put "VINFORMATD=" id;
  put "VINFORMATX=" ix;
  put "CHARINF="    ci;
run;
