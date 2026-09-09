/* GH#59 ISS-setnumlen (follow-up to #46): a numeric LENGTH inherited through a
   SET concatenation (from a 0-row template dataset carrying SDTM var lengths)
   must be kept, so an assigned value truncates to the inherited storage length.
   Also the plain in-step `length x 5;` case: the declared numeric length reaches
   the dataset descriptor (PROC CONTENTS shows Num 5, vlength=5 after read-back;
   NUMLEN-meta). Length 8 stays full precision. */
data tmpl; length x 5; stop; run;
data src;  y = 1; run;
data b; set tmpl src; x = 36.6; run;
data _null_; set b; v = vlength(x); put 'set: vlength=' v ' hex=' x hex16.; run;

data c; length x 5; x = 36.6; run;
data _null_; set c; v = vlength(x); put 'plain: vlength=' v ' hex=' x hex16.; run;
proc contents data=c; run;
