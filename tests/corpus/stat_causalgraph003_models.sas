/* STAT-CAUSALGRAPH-003: MODEL statement forms (pp.2304-2305): repeated
 * directed edges in either arrow spelling (ignored), several MODEL
 * statements with and without IDENTIFY, and an UNMEASURED variable shared by
 * the models. One VariableInfo table ("Variables in Models") over the union
 * of the models, one summary row per model, one adjustment page per model
 * whose covariate columns are the union of the models' measured covariates.
 * Invented graphs; the expected listing is a SAS 9.4 reference run of these
 * steps, the blank line SAS writes before each new page title dropped.
 */
options nodate nonumber nocenter linesize=160 pagesize=max;
title "D1 directed duplicates";
proc causalgraph;
  model "D1" A ==> B, A ==> B, B <== A, A ==> C ==> B;
  identify A ==> B;
run;
title "D4 two models";
proc causalgraph;
  model "First" Z ==> X ==> Y, Z ==> Y;
  model "Second" X ==> Y, W ==> X, W ==> Y, V ==> Y;
  identify X ==> Y;
run;
title "D5 two models unmeasured, no sets in one";
proc causalgraph;
  model "M1" Z ==> X ==> Y, U ==> Z, U ==> Y;
  model "M2" X ==> Y, X <==> Y;
  identify X ==> Y;
  unmeasured U;
run;
title "D6 two models no identify";
proc causalgraph;
  model "Aa" A ==> B;
  model "Bb" A ==> B ==> C <==> A;
run;
