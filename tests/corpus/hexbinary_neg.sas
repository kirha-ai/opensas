/* BUG-hexnegtwoscomp: HEXw./BINARYw. render negatives as their two's-complement
   bit pattern truncated to the field width (SAS 9.4), not the magnitude. */
data _null_;
  a=-5; b=-1; c=-256; g=255; h=10;
  put "neg1=" a hex4.;      /* FFFB     */
  put "neg2=" b hex4.;      /* FFFF     */
  put "neg3=" a hex8.;      /* FFFFFFFB */
  put "neg4=" c hex4.;      /* FF00     */
  put "neg5=" a binary8.;   /* 11111011 */
  put "neg6=" b binary16.;  /* all ones */
  put "pos1=" g hex4.;      /* 00FF unchanged */
  put "pos2=" h binary8.;   /* 00001010 unchanged */
run;
