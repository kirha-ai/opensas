/* NOTE-ofvarlistuninit (QA tick336 F7): "`of _numeric_` / `_all_` /
   `_character_` emit a spurious `Variable _numeric_ is uninitialized` NOTE;
   the value is correct and no phantom column appears." REPRODUCED, then FIXED
   in exec.zig's maybeNoteUninit (the reserved list names are never PDV vars —
   Language Reference: Concepts ch.25). The corpus diffs STDOUT only, so this fixture pins the VALUES
   the NOTE used to accompany; the NOTE's absence is pinned by the captured-
   diagnostics test in src/exec.zig (NOTE-ofvarlistuninit). */
data d; input a b c $; datalines;
1 2 x
3 4 y
;
run;
data _null_;
  set d;
  s = sum(of _numeric_);
  t = cats(of _character_);
  put s= t=;
run;
