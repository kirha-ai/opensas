/* Pins the Language Reference: Concepts Ch.23 interleaving rule (p.567,
   Interleaving Example 1 / Output 23.3): "The value of variables found in one
   data set but not in the other are set to missing, and the observations are
   arranged by the values of the BY variable."  (Mechanism: p.566 Execution
   Step 1 — PDV set to missing each time a new data set is read AND when the
   BY group changes.  BUG-setsourcereset.)  Two six-row inputs with the same
   six keys; exactly ONE of Tool/Fruit is populated per row, alternating
   p Awl / p Mango / q Rasp / q Papaya / ... / u Yam. */
data tools; input Code $ Tool $; datalines;
p Awl
q Rasp
r Saw
s Hoe
t Plane
u File
;
run;
data fruits; input Code $ Fruit $; datalines;
p Mango
q Papaya
r Apricot
s Mandarin
t Rambutan
u Yam
;
run;
data merged_by_code;
   set tools fruits;
   by Code;
run;
proc print data=merged_by_code;
   title 'Interleaved inventory';
run;
