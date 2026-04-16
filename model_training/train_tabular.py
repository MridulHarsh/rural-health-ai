#!/usr/bin/env python3
"""
Rural Health AI — Tabular Model Training
=========================================
Trains symptom→disease classifier from CSV/XLSX/ARFF datasets.
Caps each class at 5000 samples for fast training (~3 min on M2).

Usage:
    python train_tabular.py --data_dir /path/to/kaggle_datasets
"""

import os, sys, json, warnings, glob, argparse
import numpy as np
import pandas as pd
from pathlib import Path
from collections import Counter
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder
from sklearn.metrics import classification_report, accuracy_score
from sklearn.ensemble import RandomForestClassifier
from imblearn.over_sampling import SMOTE
from tqdm import tqdm
import joblib

warnings.filterwarnings('ignore')
OUTPUT_DIR = Path("output")
OUTPUT_DIR.mkdir(exist_ok=True)
MIN_SAMPLES = 5
RANDOM_STATE = 42

# ═══════════════════════════════════════════════════════════════
# FILE FINDERS
# ═══════════════════════════════════════════════════════════════

def find_csvs(folder):
    csvs = []
    for root, _, files in os.walk(folder):
        for f in files:
            if f.lower().endswith('.csv') and not f.startswith('.'):
                csvs.append(os.path.join(root, f))
    return csvs

def find_xlsx(folder):
    xl = []
    for root, _, files in os.walk(folder):
        for f in files:
            if f.lower().endswith(('.xlsx','.xls')) and not f.startswith('.') and '~$' not in f:
                xl.append(os.path.join(root, f))
    return xl

def load_arff_file(filepath):
    data_started = False; columns = []; rows = []
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('%'): continue
            if line.upper().startswith('@ATTRIBUTE'):
                columns.append(line.split()[1])
            elif line.upper().startswith('@DATA'):
                data_started = True
            elif data_started:
                vals = line.split(',')
                if len(vals) == len(columns): rows.append(vals)
    return pd.DataFrame(rows, columns=columns) if rows else None

def read_any_tabular(folder):
    for fp in find_csvs(folder):
        try:
            df = pd.read_csv(fp, nrows=5)
            if len(df.columns) >= 2: return pd.read_csv(fp)
        except: pass
    for fp in find_xlsx(folder):
        try: return pd.read_excel(fp)
        except: pass
    for root, _, files in os.walk(folder):
        for f in files:
            if f.lower().endswith('.arff'):
                r = load_arff_file(os.path.join(root, f))
                if r is not None: return r
    return None

# ═══════════════════════════════════════════════════════════════
# GENERIC HELPERS
# ═══════════════════════════════════════════════════════════════

def detect_target(df):
    for c in ['Disease','disease','prognosis','Prognosis','target','Target',
              'Outcome','outcome','class','Class','diagnosis','Diagnosis',
              'condition','classification','Classification','label','Label',
              'result','Result','status','Status','OUTPUT','output',
              'HeartDisease','heartdisease','cardio','Cardio',
              'stroke','Stroke','Diabetes','diabetes',
              'ASD','Class/ASD','Class/ASD Traits ','Disorder',
              'Sleep Disorder','Dataset','num']:
        if c in df.columns: return c
    last = df.columns[-1]
    if df[last].nunique() < 30: return last
    return None

def feature_to_symptoms(df, target_col, disease_label=None):
    exclude = {target_col,'id','Id','ID','Unnamed: 0','index','Unnamed: 0.1'}
    ncols = [c for c in df.columns if c not in exclude and df[c].dtype in ['int64','float64','int32','float32']]
    ccols = [c for c in df.columns if c not in exclude and c not in ncols and df[c].nunique() < 15]
    q75 = {c: df[c].quantile(0.75) for c in ncols if df[c].notna().sum() > 10}
    q25 = {c: df[c].quantile(0.25) for c in ncols if df[c].notna().sum() > 10}
    records = []
    for _, row in df.iterrows():
        if pd.isna(row[target_col]): continue
        if disease_label:
            d = disease_label if str(row[target_col]).strip().lower() in ['1','1.0','yes','positive','2','ckd'] else f"No {disease_label}"
        else:
            d = str(row[target_col]).strip()
            if not d or d.lower() in ('nan','none',''): continue
        syms = []
        for c in ncols:
            v = row[c]
            if pd.isna(v): continue
            ck = c.lower().replace(' ','_').replace('(','').replace(')','').replace('/','_')
            if c in q75 and v > q75[c]: syms.append(f"high_{ck}")
            elif c in q25 and v < q25[c]: syms.append(f"low_{ck}")
        for c in ccols:
            v = row[c]
            if pd.notna(v):
                vs = str(v).strip().lower().replace(' ','_')
                if vs not in ('0','no','false','none','nan','normal','negative',''):
                    syms.append(f"{c.lower().replace(' ','_')}_{vs}")
        if syms: records.append({'disease': d, 'symptoms': syms})
    return records

# ═══════════════════════════════════════════════════════════════
# SPECIALIZED LOADERS
# ═══════════════════════════════════════════════════════════════

def load_symptom_columns(df):
    tc = detect_target(df)
    if tc is None: return []
    scols = [c for c in df.columns if c.lower().startswith('symptom')]
    if not scols: return []
    records = []
    for _, row in df.iterrows():
        disease = str(row[tc]).strip()
        syms = [str(row[c]).strip().lower().replace(' ','_') for c in scols
                if pd.notna(row[c]) and str(row[c]).strip() not in ('0','','nan')]
        if syms and disease and disease.lower() not in ('nan',''): records.append({'disease':disease,'symptoms':syms})
    return records

def load_binary_symptoms(df, disease_label=None):
    tc = detect_target(df)
    if tc is None: return []
    bcols = []
    for c in df.columns:
        if c == tc: continue
        vals = set(str(v).strip().lower() for v in df[c].dropna().unique())
        if vals and vals.issubset({'yes','no','0','1','0.0','1.0','true','false'}): bcols.append(c)
    if len(bcols) < 2: return []
    records = []
    for _, row in df.iterrows():
        d = str(row[tc]).strip()
        if disease_label:
            d = disease_label if d.lower() in ['1','1.0','yes','positive'] else f"No {disease_label}"
        syms = [c.lower().replace(' ','_') for c in bcols if str(row[c]).strip().lower() in ('yes','1','1.0','true')]
        if syms and d and d.lower() not in ('nan',''): records.append({'disease':d,'symptoms':syms})
    return records

def load_heart(df):
    tc = detect_target(df)
    if tc is None: return feature_to_symptoms(df, df.columns[-1], "Heart Disease")
    cmap = {'cp':('chest_pain',lambda v:int(float(v))>0),'chestpaintype':('chest_pain',lambda v:str(v).strip() not in ('0','TA')),
            'trestbps':('high_blood_pressure',lambda v:float(v)>140),'restingbp':('high_blood_pressure',lambda v:float(v)>140),
            'chol':('high_cholesterol',lambda v:float(v)>240),'cholesterol':('high_cholesterol',lambda v:float(v)>240),
            'fbs':('high_fasting_blood_sugar',lambda v:int(float(v))>0),'fastingbs':('high_fasting_blood_sugar',lambda v:int(float(v))>0),
            'thalach':('high_heart_rate',lambda v:float(v)>150),'maxhr':('high_heart_rate',lambda v:float(v)>150),
            'exang':('exercise_angina',lambda v:int(float(v))>0),'exerciseangina':('exercise_angina',lambda v:str(v).strip().upper()=='Y'),
            'oldpeak':('st_depression',lambda v:float(v)>1.0),'age':('age_above_55',lambda v:float(v)>55),
            'smoke':('smoking',lambda v:int(float(v))>0),'alco':('alcohol',lambda v:int(float(v))>0),
            'ap_hi':('high_systolic_bp',lambda v:float(v)>140),'ap_lo':('high_diastolic_bp',lambda v:float(v)>90)}
    records = []
    for _, row in df.iterrows():
        tv = row[tc]
        if pd.isna(tv): continue
        hd = str(tv).strip().lower() in ['1','1.0','2','3','4','yes','positive','presence']
        d = "Heart Disease" if hd else "Healthy Heart"
        syms = []
        for ac in df.columns:
            ak = ac.lower().replace(' ','').replace('_','')
            if ak in cmap:
                try:
                    if pd.notna(row[ac]) and cmap[ak][1](row[ac]): syms.append(cmap[ak][0])
                except: pass
            if ak == 'sex':
                try: syms.append('male' if str(row[ac]).strip() in ['1','M','Male'] else 'female')
                except: pass
        if syms: records.append({'disease':d,'symptoms':syms})
    return records if records else feature_to_symptoms(df, tc, "Heart Disease")

def load_diabetes(df):
    dmap = {'glucose':(140,'high_glucose'),'bloodpressure':(90,'high_blood_pressure'),
            'bmi':(30,'obesity'),'age':(45,'age_above_45'),'pregnancies':(3,'multiple_pregnancies'),
            'insulin':(166,'high_insulin'),'skinthickness':(30,'high_skin_thickness'),
            'diabetespedigreefunction':(0.5,'family_history_diabetes')}
    tc = detect_target(df)
    if tc is None: return []
    records = []
    for _, row in df.iterrows():
        hd = str(row[tc]).strip() in ['1','1.0']
        d = "Diabetes" if hd else "No Diabetes"
        syms = []
        for ac in df.columns:
            ak = ac.lower().replace(' ','_')
            if ak in dmap:
                try:
                    if float(row[ac]) > dmap[ak][0]: syms.append(dmap[ak][1])
                except: pass
        if syms: records.append({'disease':d,'symptoms':syms})
    return records

def load_kidney(df):
    tc = detect_target(df)
    if tc is None:
        for c in df.columns:
            vals = set(str(v).strip().lower().replace('\t','') for v in df[c].dropna().unique())
            if vals.intersection({'ckd','notckd'}): tc = c; break
    if tc is None: return feature_to_symptoms(df, df.columns[-1], "Kidney Disease")
    bmap = {'htn':'hypertension','dm':'diabetes_mellitus','cad':'coronary_artery_disease','pe':'pedal_edema','ane':'anemia'}
    nmap = {'bp':(90,'>','high_blood_pressure'),'bgr':(150,'>','high_blood_glucose'),
            'bu':(50,'>','high_blood_urea'),'sc':(1.2,'>','high_serum_creatinine'),'hemo':(12,'<','low_hemoglobin')}
    records = []
    for _, row in df.iterrows():
        tv = str(row[tc]).strip().lower().replace('\t','')
        d = "Chronic Kidney Disease" if tv in ['ckd','1','yes'] else "No Kidney Disease"
        syms = []
        for ac in df.columns:
            ak = ac.strip().lower()
            if ak in bmap and str(row[ac]).strip().lower() in ('yes','1',' yes'): syms.append(bmap[ak])
            if ak == 'appet' and str(row[ac]).strip().lower() == 'poor': syms.append('poor_appetite')
            if ak in nmap:
                try:
                    v = float(row[ac]); th, op, sn = nmap[ak]
                    if (op=='>' and v>th) or (op=='<' and v<th): syms.append(sn)
                except: pass
        if syms: records.append({'disease':d,'symptoms':syms})
    return records

def load_liver(df):
    tc = detect_target(df)
    if tc is None:
        if 'Dataset' in df.columns: tc = 'Dataset'
        else: return feature_to_symptoms(df, df.columns[-1], "Liver Disease")
    lmap = {'total_bilirubin':(1.2,'high_bilirubin'),'direct_bilirubin':(0.3,'high_direct_bilirubin'),
            'alkaline_phosphotase':(200,'high_alk_phosphatase'),'alamine_aminotransferase':(45,'high_alt'),
            'aspartate_aminotransferase':(40,'high_ast')}
    records = []
    for _, row in df.iterrows():
        tv = str(row[tc]).strip()
        hd = tv.lower() in ['1','1.0','yes','positive']
        d = "Liver Disease" if hd else "No Liver Disease"
        syms = []
        for ac in df.columns:
            ak = ac.lower().replace(' ','_')
            if ak in lmap:
                try:
                    if float(row[ac]) > lmap[ak][0]: syms.append(lmap[ak][1])
                except: pass
            if 'age' in ak:
                try:
                    if float(row[ac]) > 45: syms.append('age_above_45')
                except: pass
        if syms: records.append({'disease':d,'symptoms':syms})
    return records if records else feature_to_symptoms(df, tc, "Liver Disease")

def load_stroke(df):
    tc = detect_target(df)
    if tc is None: return feature_to_symptoms(df, df.columns[-1], "Brain Stroke")
    records = []
    for _, row in df.iterrows():
        tv = str(row[tc]).strip()
        d = "Brain Stroke" if tv in ['1','1.0','yes'] else "No Stroke"
        syms = []
        for ac in df.columns:
            al = ac.lower().replace(' ','_')
            try:
                if al=='hypertension' and int(float(row[ac]))==1: syms.append('hypertension')
                if al=='heart_disease' and int(float(row[ac]))==1: syms.append('heart_disease_history')
                if 'glucose' in al and float(row[ac])>140: syms.append('high_glucose')
                if al=='bmi' and pd.notna(row[ac]) and float(row[ac])>30: syms.append('obesity')
                if al=='age' and float(row[ac])>55: syms.append('age_above_55')
                if al=='smoking_status' and str(row[ac]).lower() in ['smokes','formerly smoked']: syms.append('smoking')
            except: pass
        if syms: records.append({'disease':d,'symptoms':syms})
    return records

def load_autism(df):
    tc = None
    for c in df.columns:
        if any(x in c.lower() for x in ['asd','class','autism']): tc = c; break
    if tc is None: tc = detect_target(df)
    if tc is None: return feature_to_symptoms(df, df.columns[-1], "Autism Spectrum Disorder")
    records = []
    for _, row in df.iterrows():
        tv = str(row[tc]).strip().lower()
        d = "Autism Spectrum Disorder" if tv in ['yes','1','1.0','true','asd'] else "No ASD"
        syms = []
        for c in df.columns:
            if c == tc: continue
            cl = c.lower()
            if cl.startswith('a') and 'score' in cl:
                try:
                    if int(float(row[c]))==1: syms.append(f"autism_q_{cl}")
                except: pass
            if 'jaundice' in cl and str(row[c]).lower() in ['yes','1']: syms.append('jaundice_at_birth')
            if 'family' in cl and str(row[c]).lower() in ['yes','1']: syms.append('family_history_asd')
        if not syms:
            syms = [f"f_{c.lower().replace(' ','_')}" for c in df.columns
                    if c!=tc and pd.notna(row[c]) and str(row[c]).strip().lower() not in ('0','no','','nan','?')][:8]
        if syms: records.append({'disease':d,'symptoms':syms})
    return records

# ═══════════════════════════════════════════════════════════════
# DATASET MAP
# ═══════════════════════════════════════════════════════════════

DATASET_MAP = {
    'itachi9604_disease-symptom-description-dataset':('symptom_cols',None),
    'ehababoelnaga_multiple-disease-prediction':('symptom_cols',None),
    'uom190346a_disease-symptoms-and-patient-profile-dataset':('binary',None),
    'johnsmith88_heart-disease-dataset':('heart',None),'oktayrdeki_heart-disease':('heart',None),
    'sulianova_cardiovascular-disease-dataset':('heart',None),'rishidamarla_heart-disease-prediction':('heart',None),
    'ritwikb3_heart-disease-statlog':('heart',None),'redwankarimsony_heart-disease-data':('heart',None),
    'colewelkins_cardiovascular-disease':('heart',None),'yasserh_heart-disease-dataset':('heart',None),
    'ritwikb3_heart-disease-cleveland':('heart',None),
    'kamilpytlak_personal-key-indicators-of-heart-disease':('heart',None),
    'fedesoriano_heart-failure-prediction':('heart',None),
    'akshaydattatraykhare_diabetes-dataset':('diabetes',None),
    'mansoordaku_ckdisease':('kidney',None),
    'jainaru_thyroid-disease-data':('feature','Thyroid Disease'),
    'emmanuelfwerr_thyroid-disease-data':('feature','Thyroid Disease'),
    'yasserhessein_thyroid-disease-data-set':('feature','Thyroid Disease'),
    'uciml_indian-liver-patient-records':('liver',None),
    'jeevannagaraj_indian-liver-patient-dataset':('liver',None),
    'utkarshx27_non-alcohol-fatty-liver-disease':('liver',None),
    'fedesoriano_cirrhosis-prediction-dataset':('liver',None),
    'rabieelkharoua_alzheimers-disease-dataset':('feature',"Alzheimer's Disease"),
    'debasisdotcom_parkinson-disease-detection':('feature',"Parkinson's Disease"),
    'desalegngeb_conversion-predictors-of-cis-to-multiple-sclerosis':('feature',"Multiple Sclerosis"),
    'jillanisofttech_brain-stroke-dataset':('stroke',None),
    'deepayanthakur_asthma-disease-prediction':('feature','Asthma'),
    'rabieelkharoua_asthma-disease-dataset':('feature','Asthma'),
    'cid007_mental-disorder-classification':('auto','Mental Disorder'),
    'mdsultanulislamovi_sleep-disorder-diagnosis-dataset':('auto','Sleep Disorder'),
    'ohinhaque_ocd-patient-dataset-demographics-and-clinical-data':('feature','OCD'),
    'baselbakeer_mental-disorders-dataset':('auto_xlsx',None),
    'arashnic_adhd-diagnosis-data':('feature','ADHD'),
    'mdismielhossenabir_psychosocial-dimensions-of-student-life':('feature','Psychosocial Stress'),
    'imtkaggleteam_mental-health':('auto','Mental Health Condition'),
    'shariful07_student-mental-health':('auto','Student Mental Health Issue'),
    'bhavikjikadara_mental-health-dataset':('auto','Mental Health Condition'),
    'programmerrdai_mental-health-dataset':('auto','Mental Health Condition'),
    'osmi_mental-health-in-tech-survey':('auto','Mental Health Issue'),
    'dakshnagra_dry-eye-disease':('feature','Dry Eye Disease'),
    'faizunnabi_autism-screening':('autism',None),
    'andrewmvd_autism-screening-on-adults':('autism',None),
    'fabdelja_autism-screening-for-toddlers':('autism',None),
    'sammy123_lower-back-pain-symptoms-dataset':('feature','Lower Back Pain'),
    'cdc_chronic-disease':('feature','Chronic Disease'),
}

def load_folder(folder_path, loader_type, disease_label):
    if loader_type == 'auto_xlsx':
        xls = find_xlsx(folder_path)
        if not xls: return [], 'no xlsx'
        try: df = pd.read_excel(xls[0]); df.columns = df.columns.str.strip()
        except Exception as e: return [], f'xlsx error: {e}'
    elif loader_type == 'autism':
        df = read_any_tabular(folder_path)
        if df is None: return [], 'no readable file'
        df.columns = df.columns.str.strip()
    else:
        df = read_any_tabular(folder_path)
        if df is None: return [], 'no readable file'
        df.columns = df.columns.str.strip()
    if len(df) == 0: return [], 'empty'

    records = []
    if loader_type == 'symptom_cols':
        records = load_symptom_columns(df) or load_binary_symptoms(df, disease_label)
        if not records:
            tc = detect_target(df)
            if tc: records = feature_to_symptoms(df, tc, disease_label)
    elif loader_type == 'binary':
        records = load_binary_symptoms(df, disease_label) or load_symptom_columns(df)
        if not records:
            tc = detect_target(df)
            if tc: records = feature_to_symptoms(df, tc, disease_label)
    elif loader_type == 'heart': records = load_heart(df)
    elif loader_type == 'diabetes': records = load_diabetes(df)
    elif loader_type == 'kidney': records = load_kidney(df)
    elif loader_type == 'liver': records = load_liver(df)
    elif loader_type == 'stroke': records = load_stroke(df)
    elif loader_type == 'autism': records = load_autism(df)
    elif loader_type in ('auto','auto_xlsx'):
        records = load_binary_symptoms(df, disease_label) or load_symptom_columns(df)
        if not records:
            tc = detect_target(df)
            if tc: records = feature_to_symptoms(df, tc, disease_label)
    elif loader_type == 'feature':
        tc = detect_target(df)
        if tc: records = feature_to_symptoms(df, tc, disease_label)
    return records, 'ok'

def load_all_datasets(data_dir):
    all_records = []; stats = {}
    existing = [(fn, lt, dl) for fn, (lt, dl) in sorted(DATASET_MAP.items()) if (data_dir / fn).exists()]
    for fn, lt, dl in tqdm(existing, desc="  Loading datasets", unit="dataset", ncols=80):
        fp = data_dir / fn
        records, status = load_folder(fp, lt, dl)
        if records:
            all_records.extend(records); stats[fn] = len(records)
            tqdm.write(f"  ✅ {fn}: {len(records)} records")
        else:
            tqdm.write(f"  ⚠️  {fn}: {status}")
    for item in sorted(data_dir.iterdir()):
        if item.is_dir() and item.name not in DATASET_MAP and not item.name.startswith('.'):
            df = read_any_tabular(item)
            if df is not None and len(df) > 0:
                df.columns = df.columns.str.strip()
                tc = detect_target(df)
                if tc:
                    records = feature_to_symptoms(df, tc)
                    if records:
                        all_records.extend(records); stats[item.name] = len(records)
                        print(f"  ✅ {item.name}: {len(records)} records (auto)")
    return all_records, stats

def build_features(records):
    df = pd.DataFrame(records)
    all_syms = set()
    for s in df['symptoms']: all_syms.update(s)
    sym_list = sorted(all_syms)
    idx = {s:i for i,s in enumerate(sym_list)}
    X = np.zeros((len(df), len(sym_list)), dtype=np.float32)
    for i, syms in tqdm(enumerate(df['symptoms']), total=len(df),
                         desc="  Building features", unit="row", ncols=80):
        for s in syms:
            if s in idx: X[i,idx[s]] = 1.0
    le = LabelEncoder()
    y = le.fit_transform(df['disease'])
    dl = le.classes_.tolist()
    return X, y, sym_list, dl

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--data_dir', type=str, default=None)
    args = parser.parse_args()

    if args.data_dir: data_dir = Path(args.data_dir)
    elif Path('kaggle_datasets').exists(): data_dir = Path('kaggle_datasets')
    elif Path('../kaggle_datasets').exists(): data_dir = Path('../kaggle_datasets')
    else: print("❌ Cannot find kaggle_datasets/"); sys.exit(1)

    print("="*70)
    print("  Rural Health AI — Tabular Model Training")
    print("="*70)

    print("\n📂 Loading tabular datasets...")
    records, stats = load_all_datasets(data_dir)
    if not records: print("\n❌ No data!"); sys.exit(1)
    total = sum(stats.values())
    print(f"\n  Total: {total} records from {len(stats)} datasets")

    print("\n📊 Building features...")
    X, y, sym_list, dl = build_features(records)
    print(f"  {X.shape[0]} samples, {X.shape[1]} features, {len(dl)} classes")

    # Filter rare
    cc = Counter(y)
    valid = {c for c,n in cc.items() if n >= MIN_SAMPLES}
    mask = np.array([yi in valid for yi in y])
    X, y = X[mask], y[mask]
    le = LabelEncoder(); y = le.fit_transform([dl[i] for i in y]); dl = le.classes_.tolist()
    print(f"  After filtering: {len(dl)} classes, {len(X)} samples")

    # Top classes
    print(f"\n  Top 15 classes:")
    names = [dl[i] for i in y]
    for d, c in Counter(names).most_common(15): print(f"    {d}: {c}")

    Xtr, Xte, ytr, yte = train_test_split(X, y, test_size=0.2, random_state=RANDOM_STATE, stratify=y)
    print(f"\n  Train: {Xtr.shape[0]}, Test: {Xte.shape[0]}")

    if Xtr.shape[0] < 50000:
        try:
            mk = min(Counter(ytr).values())
            if mk >= 2:
                k = min(5, mk-1)
                Xtr, ytr = SMOTE(random_state=RANDOM_STATE, k_neighbors=k).fit_resample(Xtr, ytr)
                print(f"  SMOTE → {Xtr.shape[0]} samples")
        except: pass

    print("\n🌲 Training Random Forest (200 trees)...")
    model = RandomForestClassifier(n_estimators=200, max_depth=30, min_samples_split=5,
                                   min_samples_leaf=2, class_weight='balanced',
                                   random_state=RANDOM_STATE, n_jobs=-1, verbose=1)
    model.fit(Xtr, ytr)
    print()  # newline after RF verbose output
    acc = accuracy_score(yte, model.predict(Xte))
    print(f"  ✅ Test Accuracy: {acc:.4f}")

    print("\n💾 Saving...")
    joblib.dump(model, OUTPUT_DIR/"disease_model_rf.joblib")
    json.dump(sym_list, open(OUTPUT_DIR/"symptom_list.json",'w'), indent=2)
    json.dump(dl, open(OUTPUT_DIR/"disease_list.json",'w'), indent=2)
    if Path("risk_mapping.json").exists():
        import shutil; shutil.copy("risk_mapping.json", OUTPUT_DIR/"risk_mapping.json")
    json.dump({"model_type":"RandomForest","num_symptoms":len(sym_list),"num_diseases":len(dl),
               "accuracy":round(float(acc),4),"training_samples":int(Xtr.shape[0]),
               "datasets":len(stats),"total_records":total},
              open(OUTPUT_DIR/"model_metadata.json",'w'), indent=2)
    imps = model.feature_importances_
    top = np.argsort(imps)[::-1][:50]
    json.dump([(sym_list[i],float(imps[i])) for i in top], open(OUTPUT_DIR/"feature_importances.json",'w'), indent=2)

    print(f"\n{'='*70}")
    print(f"  ✅ Tabular model done! Accuracy: {acc:.2%}")
    print(f"  {len(dl)} diseases | {len(sym_list)} features")
    print(f"{'='*70}")

if __name__ == "__main__":
    main()
