/* BUG-charnum-parsefloat: char->num auto-conversion must follow SAS's `w.` informat,
   which REJECTS syntaxes Zig's parseFloat accepts (hex 0x1F, underscores 1_000,
   binary 0b101, commas) -> those give MISSING, not a real number. Conforming forms
   (decimal, E-notation, blanks, trailing dot) still parse. Covers both the implicit
   conversion path and the explicit input(...,w.) informat path. */
data _null_;
  hexv    = "0x1F"  + 0;  put "hex="    hexv;
  underv  = "1_000" + 0;  put "under="  underv;
  binv    = "0b101" + 0;  put "binary=" binv;
  commav  = "1,234" + 0;  put "comma="  commav;
  decv    = "3.14"  + 0;  put "dec="    decv;
  sciv    = "1e3"   + 0;  put "sci="    sciv;
  blankv  = "  42 " + 0;  put "blank="  blankv;
  dotv    = "5."    + 0;  put "dot="    dotv;
  negv    = "-7"    + 0;  put "neg="    negv;
  inhex   = input("0x1F", 8.);  put "in_hex=" inhex;
  insci   = input("1e3", 8.);   put "in_sci=" insci;
run;
