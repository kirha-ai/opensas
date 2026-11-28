/* expect-rc: 2
 * STAT-CAUSALGRAPH-003: valid MODEL forms outside the verified scope fail
 * visibly with no listing: a model made disconnected by its bidirected edges
 * (ConnectedComponents table, SAS prints it), ORDERMODELS with two models,
 * and a prescribed adjustment variable that is in only one of two models.
 * The disconnected step still gives the MODEL warnings of the SAS 9.4
 * reference run first, in the SAS order (variance before repeated edges).
 * Invented graphs.
 */
options nosyntaxcheck;
proc causalgraph; model "D3" X ==> Y, A <==> B, B <==> C, A <==> C, <==> {A B C}, {A B} <==> {B C}, <==> {Y Y X}; identify X ==> Y; run;
proc causalgraph ordermodels; model "P" X ==> Y, Z ==> X Y; model "Q" X ==> Y; identify X ==> Y; run;
proc causalgraph; model "P" X ==> Y, Z ==> X Y; model "Q" X ==> Y, W ==> X; identify X ==> Y | Z; run;
