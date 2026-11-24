/* STAT-MCMC-007: MCMC — Assignments of Parameters / Standard Distributions / Usage of Multivariate Distributions
 * Source: S154 / Chapter 80 / `Assignments of Parameters` (PDF pp. 6157–6158); S154 / Chapter 80 / `Standard Distributions` (PDF pp. 6158–6171); S154 / Chapter 80 / `Usage of Multivariate Distributions` (PDF pp. 6171–6174).
 * Discriminates: Example 80.9: Multivariate Normal Random-Effects Model
 */
options nosyntaxcheck obs=max firstobs=1 nodate nonumber nocenter linesize=160 pagesize=max nostimer nofullstimer validvarname=v7 validmemname=compatible locale=en_US;
%let syscc=0;
title; footnote;
ods _all_ close;
ods listing gpath="%sysfunc(pathname(work))";
ods graphics off;
proc datasets library=work kill nolist; quit;
ods path work.templat(update) sashelp.tmplmst(read);

title 'Multivariate Normal Random-Effects Model';
data rats;
array days[5] (8 15 22 29 36);
input weight @@;
subject = ceil(_n_/5);
index = mod(_n_-1, 5) + 1;
age = days[index];
drop index days:;
datalines;
151 199 246 283 320 145 199 249 293 354
147 214 263 312 328 155 200 237 272 297
135 188 230 280 323 159 210 252 298 331
141 189 231 275 305 159 201 248 297 338
177 236 285 350 376 134 182 220 260 296
160 208 261 313 352 143 188 220 273 314
154 200 244 289 325 171 221 270 326 358
163 216 242 281 312 160 207 248 288 324
142 187 234 280 316 156 203 243 283 317
157 212 259 307 336 152 203 246 286 321
154 205 253 298 334 139 190 225 267 302
146 191 229 272 302 157 211 250 285 323
132 185 237 286 331 160 207 257 303 345
169 216 261 295 333 157 205 248 289 316
137 180 219 258 291 153 200 244 286 324
;
proc mcmc data=rats nmc=1000 outpost=postout
seed=17 init=random nbi=200;
ods select Parameters REParameters PostSumInt;
array theta[2] alpha beta;
array theta_c[2];
array Sig_c[2,2];
array mu0[2] (0 0);
array Sig0[2,2] (1000 0 0 1000);
array S[2,2] (0.02 0 0 20);
parms theta_c Sig_c {121 0 0 0.26} var_y;
prior theta_c ~ mvn(mu0, Sig0);
prior Sig_c ~ iwish(2, S);
prior var_y ~ igamma(0.01, scale=0.01);
random theta ~ mvn(theta_c, Sig_c) subject=subject
monitor=(alpha_9 beta_9 alpha_25 beta_25);
mu = alpha + beta * age;
model weight ~ normal(mu, var=var_y);
run;
run;
quit;
