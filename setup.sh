#!/bin/bash
# ─────────────────────────────────────────────────────────
# Rural Health AI - Quick Setup Script (MacBook Air M2)
# ─────────────────────────────────────────────────────────

set -e

echo "╔══════════════════════════════════════════════════╗"
echo "║     Rural Health AI - Setup Script               ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# ── Step 1: Create Conda environment ──
echo "📦 Step 1: Setting up Python environment..."
if conda info --envs | grep -q "rural_health"; then
    echo "  Environment 'rural_health' already exists. Activating..."
    eval "$(conda shell.bash hook)"
    conda activate rural_health
else
    conda create -n rural_health python=3.11 -y
    eval "$(conda shell.bash hook)"
    conda activate rural_health
fi

# ── Step 2: Install Python dependencies ──
echo ""
echo "📦 Step 2: Installing Python dependencies..."
cd model_training
pip install -r requirements.txt -q
cd ..

# ── Step 3: Check for datasets ──
echo ""
echo "📂 Step 3: Checking datasets..."
MISSING=0
if [ ! -f "model_training/data/disease_symptom.csv" ]; then
    echo "  ⚠️  Missing: data/disease_symptom.csv"
    echo "     Download from: https://www.kaggle.com/datasets/itachi9604/disease-symptom-description-dataset"
    MISSING=1
fi
if [ ! -f "model_training/data/heart_disease.csv" ]; then
    echo "  ⚠️  Missing: data/heart_disease.csv"
    echo "     Download from: https://www.kaggle.com/datasets/johnsmith88/heart-disease-dataset"
    MISSING=1
fi
if [ ! -f "model_training/data/diabetes.csv" ]; then
    echo "  ⚠️  Missing: data/diabetes.csv"
    echo "     Download from: https://www.kaggle.com/datasets/akshaydattatraykhare/diabetes-dataset"
    MISSING=1
fi

if [ $MISSING -eq 1 ]; then
    echo ""
    echo "  ❌ Please download the missing datasets and place them in model_training/data/"
    echo "  Then re-run this script."
    exit 1
fi

echo "  ✅ All datasets found!"

# ── Step 4: Train model ──
echo ""
echo "🧠 Step 4: Training ML model..."
cd model_training
python train_model.py

# ── Step 5: Export to TFLite ──
echo ""
echo "📦 Step 5: Exporting to TFLite..."
python export_tflite.py

# ── Step 6: Copy model to Android app ──
echo ""
echo "📋 Step 6: Copying model to Android app..."
cp output/disease_model.tflite ../android_app/assets/models/
cp output/symptom_list.json ../android_app/assets/models/
cp output/disease_list.json ../android_app/assets/models/
cp output/risk_mapping.json ../android_app/assets/models/
cp output/model_metadata.json ../android_app/assets/models/
cd ..

echo "  ✅ Model files copied to android_app/assets/models/"

# ── Step 7: Check Flutter ──
echo ""
echo "🔍 Step 7: Checking Flutter installation..."
if command -v flutter &> /dev/null; then
    echo "  ✅ Flutter found: $(flutter --version | head -1)"
    echo ""
    echo "📱 Step 8: Setting up Flutter project..."
    cd android_app
    flutter pub get
    echo ""
    echo "  ✅ Flutter dependencies installed!"
    echo ""
    echo "╔══════════════════════════════════════════════════╗"
    echo "║  ✅ Setup complete!                              ║"
    echo "║                                                  ║"
    echo "║  To build the APK:                               ║"
    echo "║    cd android_app                                ║"
    echo "║    flutter build apk --release                   ║"
    echo "║                                                  ║"
    echo "║  To run on connected device:                     ║"
    echo "║    flutter run                                   ║"
    echo "╚══════════════════════════════════════════════════╝"
else
    echo "  ⚠️  Flutter not found. Install from:"
    echo "     https://docs.flutter.dev/get-started/install/macos"
    echo ""
    echo "  After installing Flutter, run:"
    echo "    cd android_app && flutter pub get && flutter build apk --release"
fi
