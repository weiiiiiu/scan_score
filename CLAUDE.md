# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Scan & Score is a Flutter mobile application for competition check-in and scoring. It allows organizers to import participant data, scan barcodes to register participants and their work, score submissions with photo evidence, and export all data.

**Key Features:**
- CSV-based participant data management
- Barcode/QR code scanning for check-in (using Google ML Kit)
- Real-time scoring with camera photo evidence
- Data export to CSV + ZIP with photos
- Dashboard with statistics and photo management

## Development Commands

### Setup and Dependencies
```bash
# Install dependencies
flutter pub get

# Check Flutter doctor
flutter doctor
```

### Running the App
```bash
# Run in debug mode
flutter run

# Run on specific device
flutter devices
flutter run -d <device-id>

# Hot reload: Press 'r' in terminal
# Hot restart: Press 'R' in terminal
```

### Building
```bash
# Build release APK (optimized for Android arm64)
flutter build apk --release --target-platform android-arm64 --obfuscate --split-debug-info=build/symbols

# Install APK to device
adb install build/app/outputs/flutter-apk/app-release.apk
```

### Code Quality
```bash
# Run linter
flutter analyze

# Format code
dart format .
```

## Architecture Overview

### State Management Pattern

The app uses **Provider** for state management with a service-oriented architecture:

1. **Services** (lib/services/) - Stateless business logic
   - `StorageService`: Path management and SharedPreferences persistence
   - `FileService`: File/directory operations (copy, delete, list)
   - `CsvService`: CSV parsing and generation (uses Isolates for performance)
   - `CameraService`: Camera operations for photo capture
   - `BarcodeService`: ML Kit barcode scanning

2. **Providers** (lib/providers/) - Stateful data management
   - `ParticipantProvider`: Main data controller for all participant CRUD operations
   - `AuthProvider`: Simple password validation (password: "admin")

3. **Models** (lib/models/)
   - `Participant`: Core data model with CSV serialization

### Data Flow

1. **Import Flow**: User picks CSV → CsvService validates & copies to app directory → ParticipantProvider loads data
2. **Check-in Flow**: Scan barcode → Find participant by memberCode → Bind workCode → Update CSV
3. **Scoring Flow**: Scan workCode → Find participant → Capture photo → Save as `workCode_score.jpg` → Update participant with score + photo path
4. **Export Flow**: Package CSV + photos directory → Create ZIP → Save to user-selected location

### File Storage Structure

```
<AppDocumentsDirectory>/
├── data.csv              # Working copy of participant data
└── evidence/             # Scoring photos directory
    ├── A001_85.jpg       # Format: workCode_score.jpg
    └── A002_92.jpg
```

### CSV Data Format

**Import format** (first 6 columns required):
```csv
参赛证号,姓名,组别,项目,队名,辅导员
A001,张三,初级组,编程,红队,李老师
```

**Working/Export format** (10 columns with runtime data):
```csv
参赛证号,姓名,组别,项目,队名,辅导员,作品码,检录状态,分数,评分照片
A001,张三,初级组,编程,红队,李老师,W001,1,85.0,/path/to/evidence/W001_85.jpg
```

### Key Technical Details

**Participant Model (lib/models/participant.dart:4)**
- `memberCode`: Unique participant ID from CSV
- `workCode`: Barcode scanned during check-in (binds participant to work)
- `checkStatus`: 0 = not checked in, 1 = checked in
- `score`: Nullable double for scoring
- `evidenceImg`: Full path to scoring photo

**CSV Processing with Isolates**
- CSV parsing/generation runs in background Isolates to prevent UI blocking
- See `CsvService._parseCsvInIsolate()` and `CsvService._generateCsvInIsolate()`

**Photo Naming Convention**
- Format: `{workCode}_{score}.jpg`
- When updating a score, the old photo is deleted and new photo is saved
- See `ParticipantProvider.submitScore()` (lib/providers/participant_provider.dart:234)

**Participant Lookup Methods**
- `findByMemberCode()`: Search by participant ID (used during check-in)
- `findByWorkCode()`: Search by work barcode (used during scoring)
- `findById()`: Search by internal row ID

## Common Development Patterns

### Updating Participant Data

Always use `ParticipantProvider.updateParticipant()` to ensure CSV persistence:

```dart
final updated = participant.copyWith(
  workCode: 'W001',
  checkStatus: 1,
);
await participantProvider.updateParticipant(updated);
```

### Handling Photo Evidence

Photos are stored in the evidence directory with automatic cleanup:
- Old photos are deleted when scores are updated
- All photos are cleared when importing new CSV data
- Photos are copied to export directory during export

### Service Initialization

Services are initialized in `main.dart:11` before app startup:
```dart
final storageService = StorageService();
await storageService.init();  // Must call init() for SharedPreferences
```

### Navigation

Use `AppRoutes` helper methods instead of direct Navigator calls:
```dart
AppRoutes.navigateTo(context, AppRoutes.scoring);
AppRoutes.goBack(context);
AppRoutes.goHome(context);  // Returns to dashboard, clears stack
```

## Screen Responsibilities

- **SplashScreen**: Loads participant data on startup, navigates to dashboard
- **DashboardScreen**: Shows statistics (total/checked/scored counts), participant table, photo grid
- **CheckinScreen**: Camera view for barcode scanning, binds workCode to participant
- **ScoringScreen**: Scans workCode, captures photo, submits score
- **ManagementScreen**: Import CSV, clear all data (requires password)
- **ExportScreen**: Export data to ZIP file

## Important Notes

- The app expects CSV files to use Chinese column headers (参赛证号, 姓名, etc.)
- Password for management operations is hardcoded as "admin" in `AuthProvider`
- CSV rows start from index 1 (row 0 is header), but Participant IDs use the row index
- All file operations should go through `FileService` for consistency
- CSV operations should go through `CsvService` to leverage Isolate-based parsing
- When adding new participant fields, update both `Participant.fromCsvRow()` and `Participant.toCsvRow()`
