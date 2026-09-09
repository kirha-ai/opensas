/* GAP-typerespec (doc-finder tick272 F4): a numeric LENGTH/ATTRIB naming a var
   already established CHARACTER (a char-literal assignment, char RETAIN init,
   char FORMAT, or a prior char LENGTH) is a fatal SAS compile error —
   "Variable X has been defined as both character and numeric." The step halts
   with 0 obs (statement-side twin of the SET conflict GH#69/#70). The ERROR is
   on stderr; stdout below pins the HALT (the conflict steps write nothing) and
   proves the VALID consistent-type / conversion programs still run.

   Only the char->num direction fires: a char type is real evidence, whereas a
   num type is often just the default guess — so a char LENGTH correcting a
   num-default guess must NOT error.
   expect-rc: 1 */

/* valid: consistent char */
data v_char; length s $8; s='hi'; run;
data _null_; set v_char; put "v_char " s=; run;

/* valid: consistent num */
data v_num; length k 8; k=5; run;
data _null_; set v_num; put "v_num " k=; run;

/* valid: numeric var, later char assignment = automatic conversion, NOT a
   type conflict (num established first; LENGTH is authoritative) */
data v_conv; length k 8; k='abc'; run;
data _null_; set v_conv; put "v_conv " k=; run;

/* valid: RETAIN with no init is a num-DEFAULT guess; a char LENGTH corrects it
   with NO conflict (over-strict guard would wrongly reject this) */
data v_retain; retain r; length r $8; r='ok'; run;
data _null_; set v_retain; put "v_retain " r=; run;

/* CONFLICT t: char assignment then numeric LENGTH — halts, writes nothing */
data c_len; x = 'abc'; length x 8; put 'never-runs'; run;

/* CONFLICT u: char assignment then numeric ATTRIB length= — halts */
data c_attrib; x = 'abc'; attrib x length=8; put 'never-runs'; run;
