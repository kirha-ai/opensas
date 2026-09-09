/* QA-tick157: locks the implicit char->numeric conversion grammar that
   BUG-charinboolean's truthy() now uses (w. informat: trimmed, signs/decimals/
   exponent accepted, commas/hex/trailing-junk -> missing -> false). Guards
   against a future truthy() rewrite that changes the accepted grammar.
   Numeric truthiness (x>1, missing->false, 0/.-> false, nonzero->true) is
   asserted here too: any change to those = regression in the shared numeric
   path the char->num twin feeds into. */
data _null_;
  /* char->num conversion grammar */
  if '+5'    then put "plus5 T";  else put "plus5 F";
  if '.5'    then put "dot5 T";   else put "dot5 F";
  if '5.'    then put "num5dot T"; else put "num5dot F";
  if '1,000' then put "comma T";  else put "comma F";
  if '00'    then put "zeros T";  else put "zeros F";
  if '1e3'   then put "e3 T";     else put "e3 F";
  if '  7  ' then put "pad7 T";   else put "pad7 F";
  if '0x10'  then put "hex T";    else put "hex F";
  if '3abc'  then put "junk T";   else put "junk F";
  /* numeric path — must stay byte-identical (no regression) */
  x = 5;   if x > 1 then put "numgt T"; else put "numgt F";
  x = 5;   if x     then put "numx T";  else put "numx F";
  x = .;   if x     then put "nummiss T"; else put "nummiss F";
  x = 0;   if x     then put "numzero T"; else put "numzero F";
  x = .A;  if x     then put "numsmiss T"; else put "numsmiss F";
  x = -3;  if x     then put "numneg T"; else put "numneg F";
run;
