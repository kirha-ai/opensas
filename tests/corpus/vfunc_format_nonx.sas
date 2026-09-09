/* V-attribute functions read a variable's FORMAT by reference (non-X forms) —
   unblocked by EXEC-varattr. corpus-vfuncs. */
data _null_;
  amt = 1234.5;
  format amt comma10.2;
  label amt = "Amount Due";
  f  = vformat(amt);
  fn = vformatn(amt);
  fw = vformatw(amt);
  fd = vformatd(amt);
  lb = vlabel(amt);
  put "VFORMAT="  f;
  put "VFORMATN=" fn;
  put "VFORMATW=" fw;
  put "VFORMATD=" fd;
  put "VLABEL="   lb;
run;
