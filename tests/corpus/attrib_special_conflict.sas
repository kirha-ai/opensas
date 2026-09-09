/* BUG-speciallistphantom (GH#79 part 1) — the TYPE side of the format guard
   must survive special-list expansion: `format _all_ best8.;` on a PDV that
   holds a CHARACTER variable is the same illegal attach SAS errors on an
   explicitly named variable ("The numeric format best8. cannot be used with
   character variable a." — the NOTE-fmtnumoncharcoerce pair). Expanding
   _ALL_ may not smuggle the format onto the char var past the guard, and it
   must report ONCE (the item rides both exec attribute lists). Loud rc 1,
   the step halts before any observation — this is why SAS programs use the
   _NUMERIC_/_CHARACTER_ forms for typed formats (attrib_special_list case D).
   expect-rc: 1 */
data m;
  a = "x"; b = 1;
  format _all_ best8.;
run;
