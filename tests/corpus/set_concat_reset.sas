/* Pins the Language Reference: Concepts Ch.23 concatenation rule (pp.562-563,
   Concatenation Example 1 / Output 23.1): "The program data vector contains
   all variables from all data sets.  The values of variables found in one
   data set but not in another are set to missing."  (Mechanism: p.562
   Execution Step 2 — the PDV is set to missing when a source hits
   end-of-file.  BUG-setsourcereset.)  Two six-row inputs sharing only the
   key and count columns; rows 7-12 (from FRUITS) must have Tool BLANK, rows
   1-6 have Fruit blank. Missing counts sit at rows 2, 5 and 9. */
data tools; input Code $ Tool $ Count; datalines;
p Awl 3
q Rasp .
r Saw 12
s Hoe 8
t Plane .
u File 41
;
run;
data fruits; input Code $ Fruit $ Count; datalines;
v Mango 63
w Mandarin 48
x Papaya .
y Quince 19
z Plum 7
zz Cherry 82
;
run;
data stacked;
   set tools fruits;
run;
proc print data=stacked;
   var Code Tool Fruit Count;
   title 'Stacked inventory';
run;
