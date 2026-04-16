#!/usr/bin/env python3
"""
Rural Health AI — Full Training Pipeline (M2 Optimized)
=======================================================
Maximizes Apple M2 hardware: Metal GPU for image training,
all CPU cores for Random Forest, mixed precision for speed.

Usage:
    python train_all.py --data_dir /path/to/kaggle_datasets
"""

import subprocess, sys, time, os
from pathlib import Path

def setup_m2_optimizations():
    """Set environment variables to maximize M2 performance."""
    
    # ── Use all CPU cores for numpy/scipy/scikit-learn ──
    cpu_count = str(os.cpu_count() or 8)
    os.environ['OMP_NUM_THREADS'] = cpu_count
    os.environ['MKL_NUM_THREADS'] = cpu_count
    os.environ['OPENBLAS_NUM_THREADS'] = cpu_count
    os.environ['VECLIB_MAXIMUM_THREADS'] = cpu_count
    
    # ── TensorFlow Metal GPU settings ──
    os.environ['TF_CPP_MIN_LOG_LEVEL'] = '2'  # Reduce TF noise
    os.environ['TF_ENABLE_ONEDNN_OPTS'] = '0'  # Avoid oneDNN warnings on ARM
    os.environ['PYTORCH_ENABLE_MPS_FALLBACK'] = '1'  # If PyTorch is ever used

    print(f"  CPU cores available: {cpu_count}")
    
    # Check Metal GPU
    try:
        import tensorflow as tf
        gpus = tf.config.list_physical_devices('GPU')
        if gpus:
            print(f"  Metal GPU: ✅ {len(gpus)} device(s) detected")
            # Allow memory growth to avoid reserving all GPU memory
            for gpu in gpus:
                tf.config.experimental.set_memory_growth(gpu, True)
        else:
            print("  Metal GPU: ⚠️  Not detected (will use CPU)")
            print("    → Fix: pip install tensorflow-metal")
    except Exception as e:
        print(f"  Metal GPU: ⚠️  Could not check ({e})")


def run(cmd, label):
    print(f"\n{'='*70}")
    print(f"  {label}")
    print(f"{'='*70}\n")
    start = time.time()
    result = subprocess.run(cmd, shell=True, env=os.environ)
    elapsed = time.time() - start
    mins = int(elapsed // 60)
    secs = int(elapsed % 60)
    status = "✅ SUCCESS" if result.returncode == 0 else "❌ FAILED"
    print(f"\n  {status} — {label} ({mins}m {secs}s)")
    return result.returncode == 0


def main():
    # Find data dir
    data_dir = None
    for i, arg in enumerate(sys.argv):
        if arg == '--data_dir' and i + 1 < len(sys.argv):
            data_dir = sys.argv[i + 1]
        elif '/' in arg or '~' in arg:
            data_dir = arg
    if not data_dir:
        for p in ['kaggle_datasets', '../kaggle_datasets', '~/Downloads/kaggle_datasets']:
            if Path(p).expanduser().exists():
                data_dir = str(Path(p).expanduser())
                break
    if not data_dir:
        print("❌ Pass --data_dir /path/to/kaggle_datasets")
        sys.exit(1)

    print("╔══════════════════════════════════════════════════════════════╗")
    print("║   Rural Health AI — Full Training Pipeline (M2 Optimized)   ║")
    print("║   Tabular (symptoms) + Images (skin/eye/lung)               ║")
    print("╚══════════════════════════════════════════════════════════════╝")
    print(f"\n  Data directory: {data_dir}")
    print()

    setup_m2_optimizations()

    total_start = time.time()

    # Step 1: Tabular — uses all CPU cores via n_jobs=-1
    s1 = run(
        f'python train_tabular.py --data_dir "{data_dir}"',
        "STEP 1/3: Training tabular model (Random Forest — all CPU cores)"
    )

    # Step 2: Images — uses Metal GPU via tensorflow-metal
    s2 = run(
        f'python train_images.py --data_dir "{data_dir}" --m2_optimize',
        "STEP 2/3: Training image models (MobileNetV2 — Metal GPU)"
    )

    # Step 3: Export tabular to TFLite
    s3 = run(
        'python export_tflite.py',
        "STEP 3/3: Exporting tabular model to TFLite"
    )

    total_elapsed = time.time() - total_start
    mins = int(total_elapsed // 60)
    secs = int(total_elapsed % 60)

    print(f"\n{'═'*70}")
    print(f"  COMPLETE — Total time: {mins}m {secs}s")
    print(f"  Tabular model: {'✅' if s1 else '❌'}")
    print(f"  Image models:  {'✅' if s2 else '❌'}")
    print(f"  TFLite export: {'✅' if s3 else '❌'}")
    print(f"\n  Next: Copy output/ files to android_app/assets/models/")
    print(f"{'═'*70}")


if __name__ == "__main__":
    main()
