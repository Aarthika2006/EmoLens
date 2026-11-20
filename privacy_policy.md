# EmoLens — Privacy Policy

**Effective Date:** November 2026
**Last Updated:** November 2026

---

## 1. Introduction

EmoLens is a mobile application designed to recognize emotions (Happy, Neutral, Sad) of individuals with Down syndrome in real time using a camera feed from an ESP32-CAM device. This privacy policy describes how EmoLens handles data, with particular attention to the **privacy and protection of a vulnerable population**.

EmoLens was designed with a **privacy-first architecture**: all data processing occurs entirely on the user's device, and no personal data is transmitted to external servers.

---

## 2. Data Collection & Processing

### 2.1 Camera Images

| Aspect | Detail |
|---|---|
| **Source** | JPEG frames from ESP32-CAM over local Wi-Fi |
| **Processing location** | Entirely on-device (Android phone) |
| **Storage** | Frames are processed in memory and **not stored** unless explicitly saved by the caregiver |
| **Transmission** | Frames travel only between the ESP32-CAM and the phone over the **local Wi-Fi network**. No frames are sent to any cloud service, remote server, or third party. |

### 2.2 Emotion Classification Results

| Aspect | Detail |
|---|---|
| **What is recorded** | Emotion label (Happy / Neutral / Sad), confidence score, timestamp |
| **Storage** | Local SQLite database on the device |
| **Purpose** | Session history, trend analysis, dashboard charts |
| **Sharing** | Data can be exported by the caregiver (CSV format) but is **never transmitted automatically** |

### 2.3 Caregiver Corrections

| Aspect | Detail |
|---|---|
| **What is stored** | Corrected emotion label and cropped face image (for adaptive learning) |
| **Storage** | App-private storage on the device |
| **Purpose** | Optional model personalization / adaptive learning |
| **Retention** | Stored until the caregiver explicitly deletes them |

---

## 3. What EmoLens Does NOT Do

- ❌ **No cloud processing** — All inference runs on-device via TensorFlow Lite.
- ❌ **No data transmission** — No images, emotions, or personal data are sent to any server.
- ❌ **No facial recognition** — EmoLens detects faces for emotion classification only. It does **not** identify individuals or store facial templates/embeddings.
- ❌ **No biometric data collection** — No fingerprints, iris scans, voice prints, or persistent facial identifiers are collected.
- ❌ **No analytics or tracking** — EmoLens does not include any analytics SDKs, advertising frameworks, or usage tracking.
- ❌ **No internet requirement** — After initial app installation and ESP32-CAM setup, the app operates entirely offline.

---

## 4. Vulnerable Population Protections

EmoLens is designed for use with **individuals with Down syndrome**, who are recognized as a **vulnerable population** requiring additional safeguards.

### 4.1 Informed Consent

- **Caregiver consent is required** before using EmoLens with any individual.
- The app displays a consent acknowledgment during the onboarding flow.
- The individual being observed should be informed about the app's purpose in an age- and ability-appropriate manner.

### 4.2 Ethical Use Guidelines

- EmoLens is intended as a **supportive tool** for caregivers, educators, and therapists — not as a diagnostic instrument.
- Emotion classifications are **probabilistic estimates** and should not be treated as definitive assessments of an individual's emotional state.
- The app should be used in a manner that **respects the dignity** of the individual being observed.
- Caregivers should not use emotion data to make consequential decisions without additional professional assessment.

### 4.3 Data Minimization

- Only the minimum data necessary for emotion classification is processed.
- Raw camera frames are discarded immediately after processing unless the caregiver explicitly chooses to save them.
- Emotion logs contain no personally identifiable information (no names, no IDs, no facial images — only labels and timestamps).

---

## 5. Data Storage & Security

| Data Type | Storage Location | Encryption | Access |
|---|---|---|---|
| Emotion logs | SQLite (app-private) | Android file-based encryption | App only |
| Caregiver corrections | App-private storage | Android file-based encryption | App only |
| Session history | SQLite (app-private) | Android file-based encryption | App only |
| App settings (IP, prefs) | SharedPreferences | Android file-based encryption | App only |
| TFLite model | App assets | Read-only | App only |

All data is stored in Android's **app-private storage**, which is sandboxed and inaccessible to other apps (unless the device is rooted).

---

## 6. Data Sharing & Export

- Caregivers may **manually export** session data as CSV files for their own records or for sharing with professionals.
- Export is **initiated only by the caregiver** — there is no automatic sharing.
- Exported files are saved to the device's shared storage (Downloads) and are under the caregiver's control.
- **No data is shared with the app developers, third parties, or any cloud service.**

---

## 7. Data Retention & Deletion

- **Emotion logs and session history** are retained on-device until the caregiver deletes them through the app's history management feature.
- **Caregiver corrections** (face crops + labels) are retained until explicitly deleted.
- **Uninstalling the app** removes all app-private data from the device.
- There is no server-side data to delete, as no data is ever transmitted.

---

## 8. Children's Privacy

If the individual being observed is a minor (under 18), additional protections apply:

- **Parental or legal guardian consent** is required.
- The app does not collect any data from children directly — all interaction is through the caregiver.
- No data is transmitted to comply with applicable children's privacy regulations (e.g., COPPA).

---

## 9. Changes to This Policy

Any changes to this privacy policy will be reflected in the app's About section and in the project documentation. The "Last Updated" date at the top of this document will be revised accordingly.

---

## 10. Contact

For questions or concerns about this privacy policy or EmoLens's data practices, please contact the project team through the project repository.

---

> **Summary:** EmoLens processes all data on-device. No images or personal data leave the phone. The app does not perform facial recognition, does not collect biometrics, and does not transmit data to any server. Caregiver consent is required for use with individuals with Down syndrome.
