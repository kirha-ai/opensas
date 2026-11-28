/* expect-rc: 1 */
/* STAT-SASHELP-001 loud gap: SASHELP.BEI (Tropical Rain Forest Tree Data) is
 * not shipped yet; referring to it must fail visibly, never yield rows. */
options nodate nonumber;
data trees; set sashelp.bei; run;
