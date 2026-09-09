/* BUG-fmtdefwidth-date: width-less date formats render at the SAS 9.4 DEFAULT
   width, not the widest natural form (doc-finder tick250; Language Reference: Concepts p.147/164:
   MONYY.->MAR13, JULIAN.->13076). MONYY./JULIAN. default 5 = the 2-DIGIT-year
   form; the word/name formats blank-pad into their field (WORDDATE/WORDDATX 18,
   WEEKDATE/WEEKDATX 29 right-justified; MONNAME/DOWNAME 9, value left).
   d=22100 = 04JUL2020 (a Saturday). */
data _null_;
  d = 22100;
  put "MONYY="    d monyy.;    /* JUL20   — default 5, 2-digit year */
  put "MONYY7="   d monyy7.;   /* JUL2020 — explicit width unchanged */
  put "JULIAN="   d julian.;   /* 20186   — default 5, yyddd        */
  put "JULIAN7="  d julian7.;  /* 2020186 — explicit width unchanged */
  put "WORDDATE=" d worddate.; /* right-justified in 18 */
  put "WEEKDATE=" d weekdate.; /* right-justified in 29 */
  put "WORDDATX=" d worddatx.; /* right-justified in 18 */
  put "WEEKDATX=" d weekdatx.; /* right-justified in 29 */
  put "MONNAME="  d monname.;  /* default 9: value left, blank-padded */
  put "DOWNAME="  d downame9.; /* explicit 9: padded into the field   */
run;
