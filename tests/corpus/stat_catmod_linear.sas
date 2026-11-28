/* STAT-CATMOD-004 original (Users Guide Example 36.1, published detergent
   data): RESPONSE 1 0 (linear response function, the probability of brand
   M), WEIGHT, the saturated bar model Softness|Previous|Temperature with
   FREQ and PROB (Residual 0 DF, effect name shortened to
   Softnes*Previou*Temperat), then a main-effects model with CLPARM,
   NOPROFILE and DESIGN in a second RUN group with a new TITLE2.
   Expected listing: the SAS 9.4 reference listing of this program,
   trailing blanks trimmed, without the blank line SAS prints before each
   titled page (base page-break layout, not CATMOD). */
options nosyntaxcheck nodate nonumber nocenter linesize=160 pagesize=max;
title; footnote;
data detergent;
input Softness $ Brand $ Previous $ Temperature $ Count @@;
datalines;
soft X yes high 19 soft X yes low 57
soft X no high 29 soft X no low 63
soft M yes high 29 soft M yes low 49
soft M no high 27 soft M no low 53
med X yes high 23 med X yes low 47
med X no high 33 med X no low 66
med M yes high 47 med M yes low 55
med M no high 23 med M no low 50
hard X yes high 24 hard X yes low 37
hard X no high 42 hard X no low 68
hard M yes high 43 hard M yes low 52
hard M no high 30 hard M no low 42
;
title 'Detergent Preference Study';
proc catmod data=detergent;
response 1 0;
weight Count;
model Brand=Softness|Previous|Temperature / freq prob;
title2 'Saturated Model';
run;
model Brand=Softness Previous Temperature
/ clparm noprofile design;
title2 'Main-Effects Model';
run;
quit;
