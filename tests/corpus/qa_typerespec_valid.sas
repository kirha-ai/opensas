/* QA tick279 over-strict lock (GAP-typerespec, ac8ef9c→23b470f): the char/num
   type-conflict guard fires ONLY on char->num (fatal) — it must never reject a
   valid consistent-type program. type_respec.sas covers the assignment-side
   cases; this pins the ATTRIB and SET-derived paths that a broadened guard
   would most likely over-reject. All steps must RUN (no HALT, no spurious
   type-conflict ERROR). */

/* ATTRIB char length then char value — char stays char, width honored */
data d1; attrib a length=$10; a='xyz'; put "d1 " a=; run;

/* ATTRIB numeric length then numeric value — num stays num */
data d2; attrib b length=8; b=3.14; put "d2 " b=; run;

/* SET brings in a char + a num column; a later char LENGTH widening the char
   col must NOT be read as a char->num conflict (types already agree) */
data src; c='hello'; n=42; run;
data d3; set src; length c $12; put "d3 " c= n=; run;

/* num-default guess (bare RETAIN) corrected by a char LENGTH — not a conflict */
data d4; retain r; length r $8; r='ok'; put "d4 " r=; run;
