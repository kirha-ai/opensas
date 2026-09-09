/* QA tick158: fmtcharrange (ee1d1af) + pictureround (b4dcff7) both edited
   format.zig UserFmtEntry (skey_hi, round). Confirm they COEXIST in one
   program, and that the numeric-discrete hash-map path (nn.) is untouched:
   - $grp mixes a char RANGE with a DISCRETE key in the middle (X), so the
     linear-scan path (has_range) must still match the discrete entry.
   - pr is a rounded PICTURE (3.98 -> 4.0).
   - nn is a pure-discrete numeric VALUE (hash-indexed). */
proc format;
  value $grp 'A'-'C'='low' 'X'='xtra' 'D'-'F'='high' other='?';
  picture pr low-high='009.9' (round);
  value nn 1='one' 2='two' other='oth';
run;
data _null_;
  length g $5;
  g=put('B',$grp.); put "B=" g;
  g=put('X',$grp.); put "X=" g;
  g=put('E',$grp.); put "E=" g;
  g=put('Q',$grp.); put "Q=" g;
  v=3.98; put v pr.;
  put "n2=" 2 nn.;
run;
