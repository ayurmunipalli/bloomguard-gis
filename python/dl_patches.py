# ============================================================
# FILE: dl_patches.py
# OWNER: A11 transformer (Stage-2, M3)
# PURPOSE: Build per-cell temporal sequences (and optional neighbor context) from the
#          datacube for the Stage-2 transformer, with leakage-safe windowing.
# INPUTS:  flattened model_dataset / datacube slices (cell x date, ordered).
# OUTPUTS: in-memory tensors / cached sequence arrays for modeling.py.
# TECHNIQUES: sliding windows through T -> label at T+H; padding/masking for cloud gaps.
# CITATIONS: —
# ============================================================

# NOTE(paper): windowing asserts every input step timestamp <= T; label at T+H only.

raise NotImplementedError(
    "TODO(A11 transformer): implement sequence/patch construction. See PLAN.md §6-A11."
)
