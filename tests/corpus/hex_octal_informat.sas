/* GAP-hexinformat + GAP-octalinformat (doc-finder tick104, Language Reference: Concepts Table 21.2):
   HEXw. reads hex digits as the integer value ("000F" -> 15, "C4A2" -> 50338);
   OCTALw. reads octal digits as the integer value ("017" -> 15, "377" -> 255).
   Verified via the INPUT() function AND the INPUT statement. $HEXw. (char hex
   -> bytes) stays the char path. OCTALw. had a wrong-value decimal fallback
   after its error — gone (377 no longer prints as 377). */
data _null_;
  a = input("000F", hex4.);
  b = input("C4A2", hex8.);
  c = input("017", octal3.);
  d = input("377", octal8.);
  e = input("414243", $hex6.); /* char path unchanged: -> "ABC" */
  put a= b= c= d= e=;
run;
data h;
  input h hex4.;
  datalines;
000F
C4A2
;
run;
proc print data=h; run;
data o;
  input o octal3.;
  datalines;
017
377
;
run;
proc print data=o; run;
