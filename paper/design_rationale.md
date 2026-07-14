# BloomGuard GIS — Design Rationale

> **Purpose.** This document records the *reasoning behind* the project's design decisions — the "why," not the "what." The agent logs (`reports/agent_logs/`) capture what each agent did and how; this file captures the methodological choices, the alternatives considered and rejected, and the findings-in-progress that were decided upstream of the pipeline. It is written to be (a) harvested by A-DOC into `paper/source_set.md`, and (b) lifted by the author into the Methods, Results, and Discussion sections of the paper.
>
> **How to use it.** Each decision below carries: the choice, the rationale, alternatives rejected, the supporting citation (to be resolved/verified by A-DOC), and any caveat. The "alternatives rejected" and "caveat" fields are the raw material for the Discussion and Limitations sections.
>
> **Citation note.** Citations are listed by author/year/venue for A-DOC to resolve to a DOI/URL. Do not treat any citation detail here as final until A-DOC verifies it; none should be reproduced verbatim from a source.

---

## 1. Study area & spatial unit

### 1.1 Study area = West Florida Shelf, 24–31°N / 87–81°W
- **Decision.** The study area is defined in code as the bounding box 24–31°N, 87–81°W, rather than the whole Gulf of Mexico or a hand-drawn coastal polygon.
- **Rationale.** This is the established study extent used by the MODIS *K. brevis* remote-sensing community; adopting it makes the work directly comparable to prior satellite HAB studies and avoids an arbitrary, hard-to-defend boundary. It concentrates on the shelf where *K. brevis* blooms and where HABSOS labels are densest.
- **Alternatives rejected.** (a) The whole Gulf basin — too large, sparse labels offshore, dilutes the signal. (b) A hand-drawn QGIS polygon — subjective and hard to justify in review; a coordinate box is reproducible and uncopyrightable. (c) A 200 m isobath clip — more ecologically precise ("the shelf") and retained as an *optional future refinement* if offshore deep-water cells degrade the model, but not needed for the MVP.
- **Citation.** Hu et al. (2022), *Harmful Algae* 117:102289 (study-area extent; MODIS *K. brevis* bloom patterns on the West Florida Shelf).
- **Caveat.** The bounding box includes some deep water beyond the shelf break; if deep-water cells prove problematic, clip to the 200 m isobath (GEBCO / USGS). Geographic generalizability beyond this box is untested.

### 1.2 Unit of analysis = grid cell × date (Risk Terrain Modeling structure)
- **Decision.** The modeling unit is a grid cell × date panel, not point samples. Point observations are aggregated into cells; features are attached per cell; risk is predicted per cell.
- **Rationale.** This mirrors the mentor's demonstrated method and his published Risk Terrain Modeling (RTM) approach: lay a grid, aggregate points into cells, predict per-cell risk. It matches the existing R/`sf` codebase and produces GIS-ready outputs directly.
- **Alternatives rejected.** Point-sample-first (predict exceedance at each sample location) — was the original framing but conflicts with the mentor's grid-first method and does not yield a mappable risk surface without a second step.
- **Citation.** Green (2022), *The Professional Geographer* 74(1):67–78 (Random Forest in an RTM framework; grid-cell risk prediction; variable-importance emphasis).

### 1.3 Cell size = 10 km × 10 km
- **Decision.** Cells are 10 km × 10 km (EPSG:5070 Albers, `cellsize = 10000`).
- **Rationale.** Three constraints converge on ~10 km: (a) it sits *above* the ~4 km MODIS L3 ocean-color pixel, so each cell aggregates several real, distinct measurements rather than up-sampling one pixel into many (which would be false precision); (b) it sits *below* the coarse environmental fields (ERA5 wind ~28 km, SMAP salinity ~40–70 km); and (c) it matches the intervention scale of coastal HAB response (advisories, closures, targeted sampling), following the RTM principle that cell size should match the scale of action, not the maximum achievable resolution.
- **Alternatives rejected.** Finer cells (e.g., 2 km) — would imply spatial precision the data cannot support; a 2 km cell contains less than one MODIS L3 pixel, so neighboring cells would repeat the same pixel value (false precision) and spread the sparse HABSOS labels even thinner. Going finer than ~4 km is only legitimate by processing MODIS L2 (~1 km), which was out of scope for the MVP.
- **Citation.** Green (2022) for the intervention-scale rationale (RTM cell-size argument).
- **Caveat.** 10 km predictions cannot localize to a specific beach; that last-mile localization requires in-situ confirmation. This is the correct division of labor (coarse screening → targeted sampling), stated plainly as a limitation.

### 1.4 Intra-cell attention drill-down (interpretability, not sub-cell forecast)
- **Decision.** For a flagged 10 km cell, the GIS layer can drill down to the native ~4 km MODIS pixels to show *where within the cell* the flag-driving conditions concentrate.
- **Rationale.** This directs response/sampling within a flagged cell without claiming forecast precision below the model's validated scale. Its trustworthiness rests on *convergence* — where the elevated pixel coincides with shallow/nearshore static context.
- **Caveat (must be stated).** This is a **diagnostic feature-concentration overlay, not a validated sub-cell forecast.** The floor is the ~4 km pixel (a stretch of coast, not a beach). It is most meaningful at short horizons; at long horizons the sub-cell field is the *pre-bloom precursor* field, which can drift with wind/current before the bloom lands.

---

## 2. Satellite data source — MODIS-only, not Sentinel-3 OLCI

- **Decision.** MODIS-Aqua L3 ocean color is the sole satellite backbone; Sentinel-3 OLCI was considered and dropped.
- **Rationale.** MODIS-Aqua provides a ~20+ year record (2002–present) — the longest available, and consistent with the record lengths used by comparable *K. brevis* MODIS studies. Record length matters because bloom events are rare and interannual variability is large; a longer record captures more positives and more extreme years.
- **Alternatives rejected / considered.** OLCI offers finer resolution (~300 m vs MODIS ~4 km L3) but only launched in 2016, so adopting it as the backbone would discard ~14 years of otherwise-usable HABSOS labels (labels are not the bottleneck — the satellite record is). OLCI and MODIS also use different bands and retrieval algorithms, so splicing them chronologically would inject an instrument-artifact discontinuity into the trend features. If OLCI is used at all, the correct design is a *parallel arm* over the overlap period, or a cross-calibrated fusion — not a chronological splice. This was deferred as future work.
- **Citation(s).** Izadi et al. (2021), *Remote Sensing* 13(19):3863 (MODIS-Aqua + XGBoost, *K. brevis*, SW Florida, ~20-year record — the closest published analog). Record-length norms drawn from a survey of ~19 satellite HAB studies (see `paper/refs_pdfs/` training-record report).
- **Caveat.** MODIS retrievals degrade in turbid nearshore (Case-2) water, exactly where *K. brevis* blooms; this bounds achievable accuracy nearshore.

---

## 3. Forecasting framing — genuine forecasting, honestly bounded

- **Decision.** The target is `HAB` at day **T+H** (H ∈ {1,3,5,7,14}), predicted from feature levels and short-term trends observed *through* day T. This is framed as forecasting, not nowcasting/detection.
- **Rationale.** What earns the word "forecasting" is that the label is a *future* event — nothing from T+1…T+H is allowed into the features. An earlier framing (features from T−7 predicting a *concurrent* sample) would have been short-lead detection, not forecasting; the future-label setup is what makes "forecasting" honest.
- **Rules enforced.** No look-ahead leakage (every feature/rolling stat computed at or before T; asserted in code and verified by the R6 reviewer). Skill is reported *per horizon* and is expected to decay with H — that decay is a result, not a failure.
- **Operational value of lead time (honest framing).** A multi-day-ahead forecast provides *temporal readiness* (pre-positioning sampling crews, early advisories, harvest decisions), **not** finer spatial targeting. The spatial pinpointing still happens later, at the detection/nowcast stage once a bloom forms. This distinction should be stated plainly.
- **Caveat.** At long horizons the forecast is weaker (see §7); the honest claim is short-lead readiness, not precise multi-day localization.

---

## 4. Feature design

### 4.1 Levels and trends are both first-class
- **Decision.** Every continuous level feature (chlorophyll-a, nFLH, SST, Kd490) gets companion *trend* features: day-over-day % change, trailing 3/5/7-day slopes, threshold-crossing flags (e.g., chl-a rising >X% DoD for ≥N consecutive days).
- **Rationale.** A cell can be high-risk because a level is already elevated *or* because it is climbing fast from a low base. The forecasting signal lives in movement as much as in level; this matches the project's original rate-of-change intuition (d/dx(FAI), chlorophyll ROC).
- **Caveat.** Relative % change is unstable when the denominator ≈ 0 (clear water, low chl); use an epsilon/log-ratio and flag it. Cloud gaps make raw day-over-day differences noisy — prefer slopes over gappy windows.

### 4.2 FAI was specified but never computed — a real gap, confirmed unresolvable from daily L3m data
- **Finding / limitation.** PLAN.md specified FAI (Floating Algae Index) and nFLH as *distinct* indices, but only nFLH was actually computed in the pipeline. nFLH was used as a proxy where FAI was intended (e.g., in the false-positive diagnostic).
- **Resolution — DROPPED, not computable.** During the bio-optical feature addition (§6), a live check of NASA OB.DAAC's file-search API confirmed that no MODIS-Aqua daily L3m product provides Rrs (or any ocean-surface reflectance) beyond 678 nm. The Hu (2009) FAI formula requires a NIR band (~859 nm) and a SWIR baseline band (~1240 nm), neither of which is distributed at the daily-mapped (L3m) product tier — only Level-2 (per-swath) processing carries those bands, which is a fundamentally different architecture (no server-side daily grid, no stream-and-discard equivalent) and was judged out of scope. This independently confirms a prior note in `R/04_satellite_features.R` (2026-07-11). **FAI remains permanently dropped from this pipeline** — nFLH continues to serve as the fluorescence-based proxy, and RBD/KBBI (Amin 2009) and the Cannizzaro (2008) bbp-discrimination score were implemented instead as the bio-optical species-discrimination features (§6).

### 4.3 Environmental features — status and the wind null result
- **Status.** Wind (ERA5) is now real for all satellite-era rows. Precipitation (CHIRPS) is blocked by a transient server-side 403 (bot-detection), retried once and deferred. Salinity (SMAP) was deliberately skipped as the lowest-value feature (40–70 km resolution against a 10 km grid — broad context only, cannot localize).
- **Finding (see §7.2).** Adding ERA5 wind produced only marginal, inconsistent metric changes — a reportable result in its own right.

---

## 5. Labeling & ground truth

- **Decision.** Binary label: *K. brevis* > 100,000 cells/L (from HABSOS), aggregated to cell × date at horizon T+H.
- **Data.** HABSOS (Harmful Algal BloomS Observing System), a NOAA/NCEI aggregation of partner-agency cell counts; the archive spans 1953–present, though usable label-days are capped by the MODIS record (~2002+). The dataset is public-domain (CC0), which is clean for publication and reuse.
- **Critical caveat (must be stated wherever labels are used).** A HABSOS non-detection is **not** proven absence — it can mean the cell-day was simply not sampled. Sampling effort is highly uneven across time and space (dense in Florida in bloom years/seasons, sparse offshore and in winter), which makes both positives and negatives uneven and recall estimates less stable in under-sampled slices.

---

## 6. Modeling approach

- **Decision.** Two stages: **Stage 1 — Random Forest** (the headline validated model), **Stage 2 — Transformer** (a committed comparison, not optional). No separate logistic/GLM modeling tier.
- **Rationale.** Random Forest is the mentor's method (Green 2022), interpretable (SHAP + variable importance), robust on tabular cell×date data, and a strong anchor. The transformer tests whether modeling temporal sequences/trends adds anything a tree ensemble with engineered trend features doesn't already capture.
- **Baselines retained.** Persistence (naïve "no change") and chlorophyll-only classifiers are kept as reference points the model must beat — they answer "compared to what?" and align with how Green (2022) benchmarks RF against a simple regression.
- **Bio-optical features (implemented, exact-equation, empirically NEGATIVE).** Species-discrimination features were added: Cannizzaro's backscatter-per-chlorophyll discrimination score (bbp(550) vs. the Morel 1988 Case-1 expected curve) and Red Band Difference/K. brevis Bloom Index (RBD/KBBI, Amin 2009) — motivated by the false-positive concentration in high-chlorophyll/high-nFLH water (§7.4). Both were implemented from the exact published equations, with authoritative NASA F0 (see NOTE(cite) below), and tested by the validation agent (§7.7). FAI was evaluated and dropped (§4.2 — not computable from daily L3m bands); no Rrs-nFLH/Soto-2015 criterion or spectral-shape (Tomlinson) feature was implemented in this pass — only the two features explicitly specified were built. **Measured outcome (§7.7): the features did NOT improve, and mildly hurt, aggregate RF forecast skill** — a legitimate negative result, reported alongside a real but insufficient targeted effect. Do not describe this addition as "evidence-backed" success; describe it as a tested hypothesis that did not pay off in aggregate.
- **NOTE(cite):** RBD and KBBI (Amin et al. 2009) are defined on **normalized water-leaving radiance nLw**, not on Rrs directly. The conversion is `nLw(λ) = Rrs(λ) × F0(λ)`, where F0 is the band-averaged extraterrestrial solar irradiance for MODIS-Aqua bands 13 (667 nm) and 14 (678 nm) — a NASA sensor constant, not a paper-derived coefficient. **F0 resolved:** 1522.491 W m⁻² µm⁻¹ (667 nm) / 1480.511 W m⁻² µm⁻¹ (678 nm), from NASA OBPG's Spectral Bandpass Integration; unit sanity-check passed (RBD lands near the 0.15 threshold scale). See `reports/bio_optical_spec.md` §1 for the exact equations and `reports/agent_logs/sat-features.md` §"F0 — authoritative source" for the full citation chain.
- **Citations.** Green (2022) (RF/RTM); Cannizzaro et al. (2008), *Continental Shelf Research* 28(1):137-158 (bbp/chl discrimination); Morel (1988), *J. Geophys. Res.* 93(C9):10749-10768 (Case-1 bbp reference curve); Amin et al. (2009), *Optics Express* 17(11):9126-9144 (RBD/KBBI).

---

## 7. Evaluation methodology & key findings

### 7.1 Evaluation protocol
- **Splits.** Three: random, temporal (train earlier years, test later), and spatial (hold out counties/blocks). The **temporal** split is the honest test of forecasting skill. Grouped/blocked splits prevent spatially adjacent cell-days from leaking across train/test.
- **Metrics.** PR-AUC and precision-at-recall-0.80 are primary, because under class imbalance ROC-AUC is misleading (the large true-negative count inflates apparent performance). Recall and false-negative rate are emphasized because, for early warning, a missed bloom is worse than a false alarm.
- **Split-integrity.** A dedicated reviewer (R-SPLIT) verifies no spatial/temporal leakage in the train/test split for both models.
- **Citation.** Saito & Rehmsmeier (2015), *PLOS ONE* (PR plot more informative than ROC under imbalance).

### 7.2 Finding — the transformer did not beat the Random Forest (a legitimate null result)
- Under the hard temporal/spatial splits, the transformer's forecasting skill was statistically indistinguishable from or below the RF's at every horizon. The RF is the headline model. This is reported as a finding, not hidden: it suggests that hand-engineered trend features in a Random Forest capture most of the forecastable signal at this data scale, so a sequence model adds little.
- **Honesty note carried in the logs.** Only the temporal and spatial comparisons are row-for-row identical between RF and transformer; the random-split comparison uses a different RNG and is indicative only — not cited as a definitive RF-vs-transformer result.

### 7.3 Finding — adding ERA5 wind barely moved the metrics (a legitimate null result)
- Adding real wind features changed PR-AUC and precision-at-recall-0.80 by only ~±0.005–0.014, inconsistently across horizons; short-horizon recall did not improve. This *falsifies* the hypothesis that the model was environmental-feature-starved and points instead to a species-discrimination gap (§7.4). Reportable as: satellite ocean-color + trend features already capture most of the forecastable signal on this shelf at these horizons; meteorological reanalysis adds little.

### 7.4 Finding — false positives concentrate in high-chlorophyll / high-nFLH water
- **Numbers (H=7 temporal, current RF).** The top chlorophyll quartile holds ~74% of all false positives (FP rate ~12× the bottom quartile); the top nFLH quartile holds ~51% (~14×); cells in the top quartile of *both* run a 12.4% FP rate vs 0.65% for neither (~19×). SST and distance-to-shore show no comparable concentration.
- **Interpretation.** This is the signature of a bio-optical species-discrimination gap: the model fires on benign high-chlorophyll/high-fluorescence water that resembles a bloom but is not *K. brevis*. It is *consistent with* (not proof of) the model's reliance on chlorophyll/nFLH trend features. It motivated testing the bio-optical features in §6 — **§7.7 reports the measured (negative) outcome of that test.**
- **Base-rate reframing.** Positive rate is ~12–16% depending on horizon. So ~25% precision at long horizons is ~2× better than random, and short-horizon precision (~0.63 at H=1) is already reasonable. The precision problem is concentrated at *long* horizons (H=7, H=14), where PR-AUC also drops (≈0.50, 0.46).

### 7.5 Scoring reconciliation (methodological integrity note)
- A discrepancy between the modeling agent's (A7) and validation agent's (A10) confusion matrices for the same model was traced to A10 wrongly excluding `month` and `doy` from its feature reconstruction and zero-filling them, corrupting its predictions. A7's numbers were correct; A10 was aligned to A7; the model was not retrained (byte-identical). Both now agree exactly. This is worth a line in the methods as evidence of the validation discipline (independent re-scoring caught and fixed a bug).

### 7.6 Current headline performance (RF, temporal split, for reference)
- PR-AUC declines with horizon: ~0.64 (H=1) → ~0.46 (H=14). This decay reflects the fundamental limit of persistence-based satellite features for multi-day forecasting.

### 7.7 Finding — the bio-optical features did NOT improve forecast skill (a legitimate negative result, with mechanistic nuance)
- **Headline (H=7 temporal, A10, 2026-07-14, bit-exact on the same 8,880 test rows).** Adding RBD/KBBI (Amin 2009) and the Cannizzaro (2008) bbp-vs-Morel score to the wind-inclusive RF **reduced** PR-AUC (0.5022 → 0.4849, −0.0173) and recall@0.5 (0.3553 → 0.3153, −0.0400); precision-at-recall-0.80 was essentially flat (0.2759 → 0.2796). Across the full 15-combo horizon×split grid, PR-AUC fell in 10/15 and rose in 5/15; recall@0.5 fell in 12/15; precision-at-recall-0.80 was a wash (down 7, up 7, flat 1) — the negative effect is concentrated at the default 0.5 threshold, not at the recall-0.80 operating point.
- **The features DID do their targeted job, partially.** On observed/clear-sky rows (chl observed in 30.2% of the test set, nFLH in 25.2%), every net false positive removed came from the top chlorophyll quartile (Q4 FP 39 → 31; Q1–Q3 unchanged); top-chl-Q4's share of all false positives fell 73.58% → 68.89%; the joint high-chl/high-nFLH false-positive rate fell 12.41% → 10.95%. This is a real, correctly-targeted error-shape change — the mechanism §7.4 hypothesized.
- **But it was not enough, and it did not reduce relative concentration.** The targeted FP cut (−22 total) was outweighed by a larger true-positive loss (−43), so net recall and PR-AUC fell. The joint FP-**concentration ratio** (top-both-quartile vs. neither) did not shrink — it **rose** from 19.09× to 22.35×, because clean-water false positives fell proportionally faster (0.65% → 0.49%) than the targeted high-chl/high-nFLH ones.
- **Honest framing.** This is a legitimate negative result: published, exact-equation K. brevis discrimination features, correctly implemented with authoritative NASA F0, did not improve — and mildly hurt — aggregate forecasting skill on this cube. They are **associated with** a small, correctly-targeted reduction in one class of false positive, not a demonstrated causal improvement in species discrimination, and the aggregate cost (lost true positives) outweighs that targeted benefit. FAI remains dropped (§4.2); only the two features specified in `reports/bio_optical_spec.md` were tested — no claim is made about untested alternatives (e.g. Soto-2015, Tomlinson spectral-shape).
- **Citation.** `\cite{amin2009rbd}`, `\cite{cannizzaro2008bbp}`, `\cite{morel1988case1}` (feature definitions); source: `reports/agent_logs/validation.md`, `outputs/tables/bio_validation_before_after.csv`, `outputs/tables/bio_fp_concentration_before_after.csv`.

---

## 8. Consolidated limitations (for the Limitations section)

- **Spatial resolution floor.** Predictions are at 10 km, bounded by MODIS L3 (~4 km); cannot localize to a specific beach without in-situ confirmation.
- **Label uncertainty.** HABSOS non-detection ≠ absence; sampling effort is uneven across season/geography, destabilizing recall estimates in under-sampled slices (e.g., spring recall was ~0 at H=7).
- **Nearshore retrieval.** MODIS ocean-color retrievals degrade in turbid Case-2 nearshore water, where *K. brevis* blooms.
- **Environmental features incomplete.** CHIRPS precipitation blocked (transient 403); SMAP salinity deferred (too coarse to localize). Wind added but had marginal effect.
- **FAI not originally computed.** A specified feature was absent until the bio-optical addition; nFLH was used as a proxy in prior diagnostics. FAI itself remains dropped (§4.2, not computable from daily L3m); RBD/KBBI and the Cannizzaro score were built instead but did not improve aggregate skill (§7.7).
- **Bio-optical species-discrimination features are a tested-and-negative addition, not a validated improvement.** RBD/KBBI (Amin 2009) and the Cannizzaro (2008) bbp-vs-Morel score reduced aggregate H=7-temporal PR-AUC and recall (§7.7) despite correctly cutting a small share of the targeted high-chlorophyll false positives. They are published equations applied off-label to MODIS-Aqua L3m 10 km cell-day aggregates, not independently re-validated for K.-brevis specificity at this resolution — report as "associated with," never "causes," and do not claim a validated sub-cell or species-level identification from them.
- **Horizon.** Forecast skill decays materially by H=14; the honest operational claim is short-lead readiness, not precise long-horizon localization.
- **Stationarity assumption.** The temporal split (train ~2003–2015, test ~2016–2021) assumes stationary bloom dynamics across the boundary; regime shifts (e.g., changing nutrient loading) could bias test-period skill.
- **Generalizability.** Trained and tested only within 24–31°N / 87–81°W; untested elsewhere.
- **Transformer comparison.** Random-split RF-vs-transformer comparison is indicative only (RNG mismatch); temporal/spatial comparisons are the valid ones.

---

## 9. Citation anchor list (for A-DOC to resolve & verify)

- Hu, C. et al. (2022). *Karenia brevis* bloom patterns on the west Florida shelf. *Harmful Algae* 117:102289. — study-area extent, MODIS integration.
- Green, J. W. (2022). The Built Environment and Predicting Child Maltreatment: An Application of Random Forests to Risk Terrain Modeling. *The Professional Geographer* 74(1):67–78. — RF/RTM method, grid-cell risk, variable importance.
- Izadi, M. et al. (2021). *Remote Sensing* 13(19):3863. — MODIS-Aqua + XGBoost *K. brevis* forecasting, ~20-year record; closest published analog.
- Cannizzaro, J. P. et al. (2008). *Continental Shelf Research* 28(1):137–158. doi:10.1016/j.csr.2004.04.007. — low backscatter-per-chlorophyll *K. brevis* discrimination.
- Amin, R. et al. (2009). *Optics Express* 17(11):9126–9144. doi:10.1364/OE.17.009126. — Red Band Difference (RBD) / *K. brevis* Bloom Index. **Corrected 2026-07-14 (A-DOC): previously miscited as *Continental Shelf Research*; RBD/KBBI are defined on nLw (=Rrs×F0), not Rrs — see `reports/bio_optical_spec.md`.**
- Soto, I. M. et al. (2015). *Remote Sensing of Environment*. — Rrs-nFLH criterion, RBD; false-positive reduction (<3%).
- Tomlinson, M. C. et al. (2009). *Remote Sensing of Environment*. — spectral-shape (SS490) discrimination; ensemble user-accuracy projection.
- Saito, T. & Rehmsmeier, M. (2015). *PLOS ONE*. — PR vs ROC under class imbalance.
- Hill, P. R. et al. (2020). HABNet. *IEEE JSTARS* (arXiv:1912.02305). — CNN-LSTM *K. brevis* detection/forecast; report accuracy/F1/Kappa, not precision/recall, and near-balanced data — not directly comparable to the imbalanced operational setting here.
- HABSOS — NOAA NCEI / USGS; CC0 public domain. — ground-truth cell counts.
- Training-record-length survey and West Florida Shelf boundary/licensing reports (in `paper/refs_pdfs/`) — supporting the record-length and study-area choices.

> **Reminder for A-DOC:** verify every entry to a resolvable DOI/URL; do not reproduce source text verbatim; mark anything unverifiable rather than inventing details. Several dates/venues above are from working memory and must be confirmed.