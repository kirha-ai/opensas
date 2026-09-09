/* BUG-macroevalnotsign: `¬` is the TWO bytes 0xC2 0xAC, and %EVAL has its own
   tokenizer whose isOperandChar calls every byte outside a short ASCII list an
   OPERAND char. So the operand scan swallowed the glyph and the operator switch
   never saw it. `%if 1 ¬= 2` lexed as `1` `¬` `=` `2`: the leftover token made
   reportEvalParse fire while the leaf `1` still tested truthy, i.e. the RIGHT
   branch AND a hard error at once. `%if ¬(1=2)` was plainly wrong (took %ELSE).
   Glued `%eval(1¬=2)` was worse still — the operand became "1¬", compared false,
   and the grammar consumed everything, so it was silently 0 with NO error.

   Table 6.3 "Macro Language Operators" (Macro Language Reference printed p.87-88)
   carries the glyph on both rows it belongs to — `¬^~ NOT` and `¬= ^= ~= NE` — so
   this one must WORK. That is the same authority that made `<>` LOUD last tick
   (absent from the table, NOTE-macroevalops): one table, both edges.

   `¦` (0xC2 0xA6) is deliberately NOT accepted: Table 6.3's OR row is `|` alone,
   and the glyph appears in the volume only in character-class lists. It stays a
   loud %EVAL error, so it is asserted in macro.zig rather than here (green
   fixtures only). */
%macro ne_spaced;  %if 1 ¬= 2 %then Y; %else N; %mend;
%macro ne_false;   %if 5 ¬= 5 %then Y; %else N; %mend;
%macro ne_zero;    %if 0 ¬= 2 %then Y; %else N; %mend;
%macro not_glyph;  %if ¬(1=2) %then Y; %else N; %mend;
data _null_;
  put "ne_spaced =[%ne_spaced]";
  put "ne_false  =[%ne_false]";
  put "ne_zero   =[%ne_zero]";
  put "not_glyph =[%not_glyph]";
  /* glued, no blanks — ordinary SAS, and the silent-0 shape */
  put "glued     =[%eval(1¬=2)]";
  put "eval_ne   =[%eval(0 ¬= 2)] [%eval(5 ¬= 5)]";
  put "eval_not  =[%eval(¬0)] [%eval(¬1)]";
  /* the glyph and its ASCII twins agree, and mix in one expression */
  put "ascii_twin=[%eval(1 ^= 2)] [%eval(1 ~= 2)] [%eval(^0)]";
  put "mixed     =[%eval(1 ¬= 2 and 3 ^= 4)]";
  put "string_ne =[%eval(abc ¬= abd)]";
run;
