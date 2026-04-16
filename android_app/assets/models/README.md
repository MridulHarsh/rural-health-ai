Place your trained model files here:
- disease_model.tflite
- symptom_list.json
- disease_list.json
- risk_mapping.json
- model_metadata.json

Generate these by running the training pipeline:
  cd model_training
  python train_model.py
  python export_tflite.py
  cp output/* ../android_app/assets/models/
