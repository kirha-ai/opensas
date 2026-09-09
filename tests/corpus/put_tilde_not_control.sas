/* GAP-puttildemodifier CONTROL — `.caret` is the NOT prefix on the hot path
   of every conditional, so carrying its source byte as token text must not
   change expression behaviour ONE BIT: `^flag` and `~flag` are both NOT,
   `^=` and `~=` are both NE (Language Reference: Concepts p.219 Table 11.3). If any of these lines
   moves, the lexer change leaked into expressions — that is the regression
   this fixture exists to catch. expect-rc: 0 */
data _null_;
  flag = 0; x = 5;
  if ^flag then put "caret-not";
  if ~flag then put "tilde-not";
  if x ^= 3 then put "caret-ne";
  if x ~= 3 then put "tilde-ne";
  if not flag then put "word-not";
run;
