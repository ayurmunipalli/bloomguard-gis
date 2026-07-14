# Bio-optical feature spec — EXACT published equations (lead-verified)

**Purpose.** Single authoritative source for the A4→A6 bio-optical species-discrimination
features. Every equation below was read directly from the PDF in `paper/refs_pdfs/` and is
transcribed verbatim with page/equation numbers. **No coefficient here is guessed or
reconstructed.** If an implementer finds an on-disk formula that disagrees with this file,
this file wins — raise it to the lead, do not silently "fix" either side.

**Provenance.** Extracted by the team lead on 2026-07-14 by reading the three source PDFs in
full. All three papers were fully legible; no equation/threshold/coefficient was ambiguous.

---

## 1. Amin et al. (2009) — RBD & KBBI
**Cite:** Amin, R., Zhou, J., Gilerson, A., Gross, B., Moshary, F., Ahmed, S. (2009).
"Novel optical techniques for detecting and classifying toxic dinoflagellate *Karenia
brevis* blooms using satellite imagery." *Optics Express* **17**(11):9126–9144.
doi:10.1364/OE.17.009126.
⚠️ NOTE(cite): this is **Optics Express**, NOT *Continental Shelf Research*. The committed
`paper/design_rationale.md` (line ~143) miscites it as Cont. Shelf Res. — A-DOC must fix.

### Bands (Fig. 1 caption, p.9134)
MODIS **Band 13 = 667 nm**, **Band 14 = 678 nm**.

### nLw conversion (§3.1 end, p.9133)
RBD/KBBI are defined on **normalized water-leaving radiance nLw**, NOT on Rrs. Amin:
"the nLw(λ) was derived by multiplying the Rrs(λ) by the extraterrestrial solar constant in
accordance with [43]" ([43] = NASA OBPG MSL12 nLw product doc).

    nLw(λ) = Rrs(λ) × F0(λ)

- Rrs from MODIS L3m `RRS.Rrs_667` / `RRS.Rrs_678` (units sr⁻¹).
- F0(λ) = band-averaged extraterrestrial solar irradiance for MODIS-Aqua band 13 / band 14.
- **Units:** F0 MUST be expressed so that Rrs[sr⁻¹] × F0 yields nLw in **W m⁻² µm⁻¹ sr⁻¹**
  (the units of Amin's RBD threshold). That requires F0 in **W m⁻² µm⁻¹** (~1.5×10³ for
  red bands), i.e. ~1500, NOT ~150 (mW cm⁻² µm⁻¹ = 10× smaller). **Mandatory sanity check:**
  after conversion, real bloom-scale RBD values must land near the 0.15 threshold scale
  (tenths), not 0.015 or 1.5 — if they don't, the F0 unit is wrong.
- F0 values are a NASA sensor constant, not a paper coefficient. Obtain the **authoritative
  MODIS-Aqua band-averaged F0** for bands 13 & 14 from NASA OBPG (the same values MSL12/
  l2gen uses to produce nLw). Document the exact numeric values, units, and source URL in
  `reports/agent_logs/sat-features.md`. If authoritative F0 cannot be obtained, **STOP**.

### RBD (Eq. 19, p.9133)
    RBD = nLw(678) − nLw(667)          [W m⁻² µm⁻¹ sr⁻¹]

### KBBI (Eq. 20, p.9134)
    KBBI = ( nLw(678) − nLw(667) ) / ( nLw(678) + nLw(667) )
    (numerator is exactly RBD; denominator = nLw(678) + nLw(667))

### Thresholds (Abstract p.9126; Detection §4.1 p.9135)
- **Detection:** RBD > 0.15 W m⁻² µm⁻¹ sr⁻¹  → "readily identifies legitimate bloom areas."
- **Classification (K. brevis):** RBD > 0.15  **AND**  KBBI > 0.3 × RBD.

Feature outputs to produce per cell×date: `rbd`, `kbbi` (continuous), plus the two published
boolean flags `rbd_detect` (RBD>0.15) and `kbbi_kbrevis` (RBD>0.15 & KBBI>0.3·RBD). Keep the
continuous scores as the primary model features; flags are interpretable companions.

---

## 2. Morel (1988) — Case-1 backscatter reference curve
**Cite:** Morel, A. (1988). "Optical modeling of the upper ocean in relation to its biogenous
matter content (case I waters)." *J. Geophys. Res.* **93**(C9):10749–10768.
doi:10.1029/JC093iC09p10749.

### Particulate scattering at 550 nm (Eq. 18, p.10759; r²=0.90, n=506)
    b_p(550) = 0.30 · C^0.62          [C = chlorophyll, mg m⁻³; valid ~0.03–30 mg m⁻³]

### Backscattering split (Eq. 17, p.10759)
    b_b = ½·b_w + b̃_b · b            (b̃_b = dimensionless particulate backscattering ratio)

### Particulate backscattering (unnumbered eq., p.10760)
Text: constant term = 0.2%; wavelength/C-varying term = 2% at λ=550, C=10⁻²; decreasing with
log₁₀C, → 0 at C=10² mg m⁻³. Numerically:

    b̃_b·b (λ) = 0.30·C^0.62 · [ 2×10⁻³ + 2×10⁻²·(½ − ¼·log₁₀ C)·(550/λ) ]

### THE reference curve (λ = 550 nm) — Cannizzaro rule #2 is defined against this
    bbp_Morel(550; C) = 0.30·C^0.62 · [ 0.002 + 0.02·(0.5 − 0.25·log₁₀ C) ]

✅ Cross-check: this is byte-identical to Amin (2009) Eq. 16 (Amin miscites its origin to
ref [42] Morel & Maritorena 2001, but the expression is verbatim Morel 1988, p.10760). Two
independent papers ⇒ high confidence the transcription is correct.

---

## 3. Cannizzaro et al. (2008) — low-bbp-per-chlorophyll discrimination
**Cite:** Cannizzaro, J.P., Carder, K.L., Chen, F.R., Heil, C.A., Vargo, G.A. (2008). "A
novel technique for detection of the toxic dinoflagellate, *Karenia brevis*, in the Gulf of
Mexico from remotely sensed ocean color data." *Continental Shelf Research* **28**(1):137–158.
doi:10.1016/j.csr.2004.04.007.

### bbp spectral power law (Eq. 14, p.146)
    bbp(λ) = bbp(λ0) · (λ0/λ)^γ
Implementation from MODIS IOP L3m (`IOP.bbp_443`, `IOP.bbp_s`), with λ0 = 443, γ = bbp_s:
    bbp(551) = bbp_443 · (443/551)^(bbp_s)
(551 nm is the MODIS green band Cannizzaro uses as "bbp(550)"; treat bbp(551) ≡ bbp(550).)
NOTE(cite): the OB.DAAC IOP L3m suite is GIOP-based; bbp(λ)=bbp(λ0)(λ0/λ)^S with S=`bbp_s`.

### γ vs Chl (Eq. 16, p.147) — provided for reference; NOT needed for the discrimination score
    γ = 0.1 + 1.9/(1 + Chl)

### THE classification rule (§6.1, p.150, Fig. 9C) — verbatim criteria
A pixel/cell is positively flagged as *K. brevis* when **BOTH**:
  1. **Chl > 1.5 mg m⁻³**, AND
  2. **bbp(550) < bbp_Morel(550; Chl)**  (observed backscatter falls BELOW the Morel-1988
     Case-1 reference curve of §2).
Paper: "all observations with (1) Chlorophyll concentrations greater than 1.5 mg m⁻³ and (2)
bbp(550) values less than the Morel (1988) relationship contain greater than 10⁴ cells l⁻¹ of
K. brevis … these two conditions shall serve as the initial criteria for classifying K.
brevis from space." (p.150)

Supporting context (p.153): K. brevis particulate backscattering ratio bbp/bp **< 1.0%** vs
**> 1.0%** for high-chl non-K.brevis (diatom) waters — the physical basis for "anomalously
low backscatter per unit chlorophyll."

### Feature outputs to produce per cell×date
- `bbp_551`             — derived observed backscatter at 551 nm (power law above).
- `bbp_morel_550`       — Morel-1988 expected bbp(550) at the cell's Chl (§2 reference curve).
- `bbp_ratio_morel`     — bbp_551 / bbp_morel_550   (continuous discrimination SCORE; <1 ⇒
                          below expectation ⇒ K.-brevis-like). This is the primary model
                          feature — a smooth score, not just the boolean.
- `bbp_deficit`         — bbp_morel_550 − bbp_551   (alt. additive form; keep both, cheap).
- `cannizzaro_kbrevis`  — boolean: (Chl > 1.5) AND (bbp_551 < bbp_morel_550). Interpretable
                          companion flag = the paper's exact published rule.

Chl input = the cube's existing `chlor_a` (MODIS `CHL.chlor_a`), same cell×date. Where Chl or
bbp inputs are missing (cloud/no retrieval), the score is NA (flag it — do NOT zero-fill;
follow the existing sat-features missingness convention).

---

## 4. Hard rules for implementers (A4b, A6, R4, R6)
- **Additive only.** These features are NEW columns joined alongside the untouched
  `satellite_features.parquet`. Do not modify or rebuild the existing MODIS cube (M1/M2).
- **FAI stays DROPPED** (design_rationale §4.2 — not computable from daily L3m). Do not add it.
- **No look-ahead.** Every bio-optical feature is computed from bands observed **at or before
  T** for the cell — identical timestamp discipline as all other features (§2.2). Trend
  variants of these scores (if A6 adds any) obey the same rule; R6 re-asserts on the new cols.
- **Stream-and-discard, resumable.** Per date: download the 4 global L3m files → clip to
  24–31N/87–81W → aggregate to the 10 km grid → append rows → `unlink()` raw files. Checkpoint
  by date (skip dates already in the output). Pull the SAME date set the existing cube uses so
  the join is 1:1 (this is the project's "full satellite era" — do it in one pass).
- **STOP conditions:** (a) any of the 4 products missing for the archive (not just one cloudy
  day); (b) authoritative F0 unobtainable; (c) the RBD unit sanity-check fails. STOP and report
  to the lead — do not approximate.
