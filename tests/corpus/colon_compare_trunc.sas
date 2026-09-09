/* QA-tick133: the colon (=:) comparison modifier truncates the LONGER operand
   to the length of the shorter one, and it does so in BOTH operand orders
   (Language Reference: Concepts comparison-operators). Regression guard for the colon-compare length
   handling — an uncovered boundary (existing coverage never put the short
   operand on the left, nor compared two equal-length values via =:). */
data _null_;
  a = "ABCDEF";
  if a  =: "ABC"    then put "1 match"; else put "1 nomatch";
  if "ABC" =: a     then put "2 match"; else put "2 nomatch";
  if a  =: "ABX"    then put "3 match"; else put "3 nomatch";
  if "ABCDEF" =: a  then put "4 match"; else put "4 nomatch";
run;
