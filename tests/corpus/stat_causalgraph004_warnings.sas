/* STAT-CAUSALGRAPH-004: IDENTIFY role-variable messages of joint effects
 * (p.2303). Message texts and order are those of a batched SAS 9.4
 * reference run of these invented graphs: a treatment, outcome or
 * prescribed variable missing from one model is dropped there with a
 * warning (treatments, then outcomes, then adjustment variables); one in no
 * model is ignored; a joint effect with no valid set gets the two-sentence
 * NOTE, also for one treatment with two outcomes.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
proc causalgraph;
  model "A" X1 X2 ==> Y, Z ==> X1 Y;
  model "B" X1 ==> Y, Z ==> X1 Y;
  identify X1 X2 ==> Y;
run;
proc causalgraph;
  model "M1" X1 X2 ==> Y1 Y2, Z ==> X1 Y1, W ==> Y2;
  model "M2" X1 ==> Y1, Z ==> X1 Y1;
  identify X1 X2 ==> Y1 Y2 | W;
run;
proc causalgraph;
  model "J10" X1 X2 ==> Y, Z ==> X1 Y;
  identify X1 X2 Q ==> Y | R;
run;
proc causalgraph;
  model "J3" W ==> X Z1, Z1 ==> Y1, V ==> Z1 Y2, X ==> Y1 Y2;
  identify X ==> Y1 Y2;
  unmeasured W V;
run;
proc causalgraph;
  model "S" X ==> Y, U ==> X Y;
  identify X ==> Y;
  unmeasured U;
run;
