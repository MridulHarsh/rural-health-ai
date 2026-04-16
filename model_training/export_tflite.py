#!/usr/bin/env python3
"""
Export trained tabular model to TFLite via knowledge distillation (RF → MLP).
Image models are already exported by train_images.py.

Usage:
    python export_tflite.py
"""

import os, json
import numpy as np
from pathlib import Path
import joblib
from tqdm import tqdm

os.environ['TF_CPP_MIN_LOG_LEVEL'] = '2'
import tensorflow as tf
from tensorflow import keras
from sklearn.model_selection import train_test_split

OUTPUT_DIR = Path("output")

def main():
    print("="*60)
    print("  Rural Health AI — TFLite Export (Tabular Model)")
    print("="*60)

    rf_path = OUTPUT_DIR / "disease_model_rf.joblib"
    if not rf_path.exists():
        print("❌ No trained model found. Run train_tabular.py first.")
        return

    print("\n📂 Loading trained Random Forest...")
    rf = joblib.load(rf_path)
    sym_list = json.load(open(OUTPUT_DIR / "symptom_list.json"))
    dis_list = json.load(open(OUTPUT_DIR / "disease_list.json"))
    nf, nc = len(sym_list), len(dis_list)
    print(f"  Features: {nf}, Classes: {nc}")

    print("\n🔄 Knowledge distillation: RF → MLP...")
    np.random.seed(42)
    n = max(50000, nc * 500)
    X_syn = np.zeros((n, nf), dtype=np.float32)
    for i in tqdm(range(n), desc="  Generating synthetic data", unit="sample", ncols=80):
        k = np.random.randint(2, min(9, nf + 1))
        idx = np.random.choice(nf, k, replace=False)
        X_syn[i, idx] = 1.0

    print("  Getting RF predictions...")
    y_soft = rf.predict_proba(X_syn).astype(np.float32)
    y_hard = rf.predict(X_syn)
    print("  ✅ Predictions complete")
    y_onehot = keras.utils.to_categorical(y_hard, nc)
    y_blend = 0.7 * y_soft + 0.3 * y_onehot

    Xtr, Xv, ytr, yv = train_test_split(X_syn, y_blend, test_size=0.1, random_state=42)
    _, _, _, yv_hard = train_test_split(X_syn, y_hard, test_size=0.1, random_state=42)

    print("\n🧠 Training MLP...")
    mlp = keras.Sequential([
        keras.layers.Input(shape=(nf,)),
        keras.layers.Dense(128, activation='relu'),
        keras.layers.BatchNormalization(),
        keras.layers.Dropout(0.3),
        keras.layers.Dense(64, activation='relu'),
        keras.layers.BatchNormalization(),
        keras.layers.Dropout(0.2),
        keras.layers.Dense(32, activation='relu'),
        keras.layers.Dense(nc, activation='softmax')
    ])
    mlp.compile(optimizer=keras.optimizers.Adam(0.001),
                loss='categorical_crossentropy', metrics=['accuracy'])

    mlp.fit(Xtr, ytr, validation_data=(Xv, yv), epochs=100, batch_size=256,
            callbacks=[keras.callbacks.EarlyStopping(patience=10, restore_best_weights=True),
                       keras.callbacks.ReduceLROnPlateau(factor=0.5, patience=5)],
            verbose=1)

    agreement = np.mean(np.argmax(mlp.predict(Xv), axis=1) == yv_hard)
    print(f"\n  MLP-RF agreement: {agreement:.2%}")

    print("\n📦 Converting to TFLite...")
    converter = tf.lite.TFLiteConverter.from_keras_model(mlp)
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_types = [tf.float16]
    tflite = converter.convert()

    path = OUTPUT_DIR / "disease_model.tflite"
    with open(path, 'wb') as f: f.write(tflite)
    size = os.path.getsize(path) / (1024*1024)
    print(f"  ✅ Saved disease_model.tflite ({size:.2f} MB)")

    meta = json.load(open(OUTPUT_DIR / "model_metadata.json"))
    meta["tflite_size_mb"] = round(size, 2)
    meta["mlp_rf_agreement"] = round(float(agreement), 4)
    json.dump(meta, open(OUTPUT_DIR / "model_metadata.json", 'w'), indent=2)

    # List all output files
    print(f"\n📋 All output files:")
    for f in sorted(OUTPUT_DIR.iterdir()):
        if not f.name.startswith('.'):
            sz = os.path.getsize(f)
            if sz > 1024*1024:
                print(f"    {f.name} ({sz/1024/1024:.1f} MB)")
            else:
                print(f"    {f.name} ({sz/1024:.0f} KB)")

    print(f"\n{'='*60}")
    print(f"  ✅ Export complete!")
    print(f"  Copy output/ contents to android_app/assets/models/")
    print(f"{'='*60}")

if __name__ == "__main__":
    main()
