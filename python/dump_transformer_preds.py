# ============================================================
# FILE:       python/dump_transformer_preds.py
# PURPOSE:    P0-C support. Dump per-row TEST predictions for the FROZEN
#             transformer (.pt files, M3) at each horizon x {temporal, spatial}
#             so R can block-bootstrap the RF-vs-transformer PR-AUC delta CI.
#             The transformer is frozen; its TEST sets (temporal year>=2016,
#             spatial holdout blocks) are UNCHANGED by the P0-A/P0-B repairs
#             (those drop only training rows), so these predictions are the
#             valid frozen comparators.
# INPUTS:     outputs/models/transformer_H{H}_{split}.pt  (state_dict + meta)
#             data/processed/model_dataset.parquet
# OUTPUTS:    outputs/tables/predictions_transformer.parquet
#             columns: horizon, split, cell_id, date_T, prob, act
# NOTE:       Reproduces the transformer's own get_splits() (dl_dataset.py) to
#             recover test_idx + the train medians/scale used at training, then
#             loads the frozen weights and runs predict(). random split skipped
#             (RNG-mismatched vs RF; not cited — design_rationale.md).
# ============================================================
import os, sys
import numpy as np
import pandas as pd
import torch
from sklearn.metrics import average_precision_score

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from dl_dataset import (
    load_and_preprocess, get_feat_cols, get_splits, build_cell_index,
    build_all_sequences, compute_train_medians, compute_train_stats,
    HABSequenceDataset, HORIZONS, SEQ_LEN,
)
from torch.utils.data import DataLoader
from modeling_transformer import (
    HABTransformer, predict, D_MODEL, N_HEADS, N_LAYERS, FFN_DIM, DROPOUT,
    BATCH_SIZE, DEVICE, PARQUET, OUT_MODELS, OUT_TABLES,
)

def main():
    print("[pC] Loading data ...", flush=True)
    df = load_and_preprocess(PARQUET)
    cell_index = build_cell_index(df)
    rows = []
    for H in HORIZONS:
        target_col = f"HAB_H{H}"
        h_df = df[df[target_col].notna()].copy().reset_index(drop=True)
        h_df["_orig_label"] = h_df[target_col].astype(int)
        feat_cols = get_feat_cols(df, H)
        splits = get_splits(h_df, H)
        for split_name in ("temporal", "spatial"):
            train_idx, test_idx = splits[split_name]
            pt = os.path.join(OUT_MODELS, f"transformer_H{H:02d}_{split_name}.pt")
            if not os.path.exists(pt):
                print(f"[pC] MISSING {pt} — skip", flush=True); continue
            ckpt = torch.load(pt, map_location="cpu", weights_only=False)
            # Use the FROZEN preprocessing stored in the checkpoint (exact
            # reproduction): feat_cols (85, pre-bio), train medians, z-score stats.
            # Recomputing would mis-match — the parquet now has bio columns.
            feat_cols   = ckpt["feat_cols"]
            medians     = ckpt["medians"]
            scale_stats = ckpt["scale_stats"]
            seqs, masks = build_all_sequences(h_df, df, cell_index, feat_cols,
                                              medians, scale_stats=scale_stats, seq_len=SEQ_LEN)
            labels = h_df["_orig_label"].values
            te_seqs, te_masks, te_labels = seqs[test_idx], masks[test_idx], labels[test_idx]
            n_feat = ckpt.get("n_features", te_seqs.shape[2])
            model = HABTransformer(n_features=n_feat, seq_len=ckpt.get("seq_len", SEQ_LEN),
                                   d_model=D_MODEL, n_heads=N_HEADS, n_layers=N_LAYERS,
                                   ffn_dim=FFN_DIM, dropout=DROPOUT).to(DEVICE)
            model.load_state_dict(ckpt["state_dict"])
            te_loader = DataLoader(HABSequenceDataset(te_seqs, te_masks, te_labels),
                                   batch_size=BATCH_SIZE, shuffle=False)
            probs, labs = predict(model, te_loader)
            pr = average_precision_score(labs, probs) if len(np.unique(labs)) > 1 else float("nan")
            print(f"[pC] H={H} {split_name}: n_test={len(labs)} PR-AUC={pr:.4f} "
                  f"(model_results transformer row should match)", flush=True)
            sub = h_df.iloc[test_idx]
            rows.append(pd.DataFrame({
                "horizon": H, "split": split_name,
                "cell_id": sub["cell_id"].values,
                "date_T": pd.to_datetime(sub["date_T"].values),
                "prob": probs.astype(float), "act": labs.astype(int),
            }))
    out = pd.concat(rows, ignore_index=True)
    op = os.path.join(OUT_TABLES, "predictions_transformer.parquet")
    out.to_parquet(op, index=False)
    print(f"[pC] wrote {op}: {len(out)} rows, {out.groupby(['horizon','split']).size().shape[0]} combos", flush=True)

if __name__ == "__main__":
    main()
