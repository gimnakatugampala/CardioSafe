# CardioSafe

CardioSafe is a native SwiftUI application for walking activity, personal health records, nearby care discovery and patient-to-hospital SOS coordination. It provides separate patient and hospital workspaces, with layouts adapted for iPhone and iPad.

The application is a coursework prototype. Its Firebase authentication, record synchronisation and communication between patient and hospital accounts use a real backend. Ambulance journeys are simulated; the app does not contact an operational emergency dispatch service.

## Main features

### Patient workspace

- Account registration, sign-in, email verification and password recovery.
- Personal profile and emergency contact details.
- Dashboard with available steps, distance and heart-rate information from HealthKit.
- Walking sessions with map routes, walking time, rest periods, available health measurements and saved summaries.
- Walking destinations, return-to-start routing and session recovery.
- Hospital search, map exploration and available department queue counts.
- SOS submission, journey status updates, simulated ambulance tracking and recovery of an active request after restart.
- Optional automatic SOS demonstration using qualifying health samples and a cancellable countdown; this is not clinically validated monitoring.
- PDF import, document scanning on supported hardware, on-device text recognition and reviewed document text.
- Once-only, daily and weekly personal reminders.
- Account-based synchronisation of supported structured records, plus account and private-data deletion controls.
- App lock, Dynamic Type, dark appearance, accessibility labels, walking shortcuts and read-aloud controls.

### Hospital workspace

- A separate interface for verified staff assigned to a hospital.
- Overview of incoming SOS requests and department queues.
- Request acceptance, ambulance assignment and subsequent journey actions.
- Confirmation of arrival at the patient, pickup, hospital arrival and handover completion.
- Department queue updates and alerts for new requests while the app is open.

### iPad adaptation

Regular-width layouts use patient and hospital sidebars. Wider windows provide dashboard columns, hospital results beside the map, a document list beside its PDF preview, and hospital requests beside their details. Active walking can place its controls beside the map. Compact windows retain the compact navigation and stacked layouts.

## Technology and architecture

The project uses Swift, SwiftUI and MVVM. Views present information, ViewModels manage interaction and state, and services/stores encapsulate platform APIs, persistence and backend access.

| Technology | Use |
| --- | --- |
| HealthKit | Available health samples and activity history |
| MapKit and Core Location | Maps, hospital discovery, routes, location and geofence reminders |
| Vision and VisionKit | On-device document text recognition and supported document scanning |
| PDFKit | PDF presentation |
| App Intents | Walking commands exposed through Apple Shortcuts |
| UserNotifications | Reminders and local notification presentation |
| LocalAuthentication | Device authentication for app lock |
| Core Data and local stores | Walking plans and local application persistence |
| Firebase Authentication | Account identity, email verification and password recovery |
| Cloud Firestore | Private structured records, hospital queues and SOS state |
| Swift Testing | Tests for core application logic and integration scenarios |

## Requirements

- A Mac running a macOS version compatible with Xcode 26.6.
- Xcode 26.6, the development version used for this project, or a compatible later version.
- iOS/iPadOS 26.5 or later, matching the current deployment target.
- An installed iPhone or iPad simulator runtime.
- Internet access for Swift Package Manager resolution, Firebase and online map/routing requests.
- The project’s Firebase client configuration file, `CardioSafe/GoogleService-Info.plist`.
- An Apple development team configured in Xcode when needed for signing, secure account storage and system App Shortcut execution.

Firebase dependencies are managed through Swift Package Manager. The repository includes `Package.resolved`; CocoaPods is not required.

## Build and run

1. Clone the repository and open the project:

   ```sh
   git clone https://github.com/gimnakatugampala/CardioSafe.git
   cd CardioSafe
   open CardioSafe.xcodeproj
   ```

2. Confirm that the Firebase client configuration is present at:

   ```text
   CardioSafe/GoogleService-Info.plist
   ```

   This file is kept with the project. If it is absent from the assessment copy, request it from the student and place it at the path above. Ensure the file is included in the CardioSafe app target. The shared backend configuration must identify the Firebase project `cardio-safe` and the registered bundle identifier `gimnak.CardioSafe`. Do not replace it with a configuration from an unrelated Firebase project.

3. Allow Xcode to resolve Swift package dependencies. If required, use **File → Packages → Resolve Package Versions**.
4. Select the **CardioSafe** scheme and an iOS Simulator destination, such as **iPhone 17 Pro Max** or **iPad Pro 11-inch**. Select an iOS/iPadOS destination rather than My Mac or Apple Vision.
5. In **Signing & Capabilities**, select an available development team if Xcode requests one. Preserve the application capabilities and keychain access group in `Config/CardioSafe.entitlements`. Do not use an unsigned build to evaluate secure sign-in.
6. Choose **Product → Run**, or press **Command-R**.
7. Complete or skip onboarding. For account features, open **Profile → Sign in or create account**.

To build from Terminal after setup, use an installed simulator name:

```sh
xcodebuild -resolvePackageDependencies \
  -project CardioSafe.xcodeproj -scheme CardioSafe

xcodebuild -project CardioSafe.xcodeproj -scheme CardioSafe \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build
```

Use `xcrun simctl list devices available` to check the simulator names installed on the assessment Mac.

## Backend access for markers

The shared assessment backend is **Firebase project `cardio-safe`**, using Firebase Authentication and the default Cloud Firestore database in **Mumbai (`asia-south1`)**.

Markers normally reach the backend through the running application. No service-account key, administrator token or Firebase Console administrator access is needed for this workflow.

| Access | How to obtain it | What it permits |
| --- | --- | --- |
| Patient | Create a patient account in the app and verify its email, or use a patient account supplied privately | Own profile and records, care discovery and patient SOS actions |
| Hospital | Sign in as `enwarelabs@gmail.com` using the password supplied privately | Staff operations for Asiri Central only |
| Firebase Console | Optional access must be granted separately to the marker's own Google account | Only the permissions explicitly granted; console access is not publicly available |

**Obtain the hospital test password through the private LMS assessment channel. No password is included in this README.** If the password is missing from the private submission, contact the student before evaluating hospital access.

The hospital test account has a verified email and trusted staff claims assigning it to `demo-asiri-central`. Successful sign-in opens the hospital workspace automatically. Ordinary patient registration does not grant staff access.

For an already-authorised marker, the project can be opened at [Firebase Console](https://console.firebase.google.com/project/cardio-safe/overview). This link does not grant permission by itself, and read-only console access has not been automatically provisioned.

### Data and permissions

- Private account records are stored under `users/{uid}`, including structured records, supporting record chunks and active SOS recovery information.
- Hospital information is stored under `hospitals/{hospitalId}`. Related department and SOS request collections support queues and request progression.
- Private records are restricted to their owner. Hospital operations require verified staff claims and the appropriate hospital assignment.
- `Firebase/firestore.rules` contains the application rules. Running the app against the shared backend does not require publishing these rules again.
- `Firebase/manage_staff.py` is an administrator utility. It requires trusted administrator credentials and is not a marker setup step or part of the iOS client.
- PDF files remain local. Supported document text and structured records can sync, but a new device does not automatically receive the original PDF files.

### Other external services

MapKit provides map and place functionality. Some pedestrian routing scenarios also use `routing.openstreetmap.de`. These services are reached through the app and do not require a separate marker account. Availability depends on connectivity and service responses.

## Suggested assessment walkthrough

1. Run two application instances, using separate simulators.
2. Sign into a patient account on the first and the hospital test account on the second.
3. Explore the dashboard, Find Care, walking controls and Records on the patient device.
4. Submit a patient SOS request through the app.
5. Open **SOS requests** in the hospital workspace and select the request.
6. Accept it, assign the ambulance and follow the permitted journey actions as they become available. The simulated journey includes a timed wait before arrival confirmation.
7. Observe the patient application's updated status and tracking presentation.
8. Complete pickup, hospital arrival and handover using the hospital controls.
9. Repeat navigation on iPad in portrait and landscape to inspect the adaptive layouts.

The patient and hospital must be signed into different accounts. The hospital test account is scoped to the configured assessment hospital; arbitrary facilities found on the map are not automatically connected to dispatch or live queues.

## Simulator permissions and sample data

- **Health:** Use the app's simulator sample-data control when available, approve the requested Health access and refresh. A simulator has no physical heart-rate sensor; displayed test samples are not live physical measurements.
- **Location:** Allow location access when requested. Configure a simulated location through Xcode's location simulation controls. Colombo coordinates are useful for the supplied hospital setup. Background region reminders require the relevant location permission.
- **Notifications:** Allow notifications to test reminders and foreground hospital alerts. A local test notification or injected simulator push is not proof of Firebase Cloud Messaging/APNs delivery.
- **PDFs:** Save a PDF in the simulator's Files app. Open **Records → Documents → Import PDF**, choose the file, review it and save it. Camera scanning requires supported hardware; PDF and image import can be demonstrated in the simulator.
- **App lock:** Use simulator-supported device authentication when configured. Passcodes and passwords should be entered directly into the simulator.
- **Appearance:** Select the app's light, dark or system appearance preference. Test larger text sizes separately through the simulator's accessibility settings.

## Tests

Open the **CardioSafe** scheme and choose **Product → Test** (**Command-U**). The test target uses Swift Testing.

```sh
xcodebuild -project CardioSafe.xcodeproj -scheme CardioSafe \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' test
```

Tests cover walking and recovery, reminders, SOS transitions, automatic SOS conditions, account isolation, synchronisation, deletion and related logic. Some backend integration tests are explicitly opt-in. Do not enable live account-deletion checks against a marker's or an existing user's account; the dedicated integration workflow creates a disposable identity.

## Troubleshooting

| Problem | Check |
| --- | --- |
| Account services are not connected | Confirm the project plist is present, included in the app target and belongs to `cardio-safe` with the expected bundle identifier |
| Installation could not save sign-in securely | Run a correctly signed simulator build with the project's keychain entitlement; do not remove capabilities to bypass the message |
| Patient interface appears for a hospital login | Confirm the correct staff account was used; refresh its access or sign in again after administrator assignment |
| Hospital access is pending | Check email verification and the account's trusted hospital assignment |
| No health values | Check sample availability and permissions; load simulator samples where supported |
| Hospitals are missing | Check connectivity, move/search the intended map area, or configure a simulated Colombo location |
| Notifications do not appear | Check notification permission, the scheduled time and whether the required app/connection state is available |
| A restored document has no local PDF | Only its supported structured information was synced; import the original PDF on this device |

## Known limitations

- This prototype does not dispatch a real ambulance. Vehicle movement is simulated.
- Queue counts are assessment data maintained through the hospital workspace, not verified operational hospital feeds.
- The automatic SOS demonstration is not a diagnostic feature or continuous background medical monitor.
- Production remote push delivery has not been established by the local notification/simulator workflows.
- Spoken Siri and complete spoken VoiceOver traversal have simulator limitations and were not fully verified.
- Physical health sensor accuracy, GPS performance and real-device battery behaviour have not been established by simulator testing.

## Public repository and configuration

This README contains no passwords, API key values or authentication tokens. Hospital test credentials must be shared privately. Do not place passwords, administrator tokens, service-account credentials, signing keys or private submission material in source comments, screenshots or test fixtures.

`GoogleService-Info.plist` remains part of the project as requested. Backend access is controlled by Firebase Authentication, trusted staff assignments and Firestore security rules; possession of the client configuration does not grant administrator access.

## Project structure

```text
CardioSafe/
  Models/       Application data types
  ViewModels/   Interaction and application state
  Views/        Patient, hospital and shared SwiftUI screens
  Services/     Platform integration, backend access and persistence
  Navigation/   Navigation definitions
  Design/       Shared appearance
CardioSafeTests/ Swift Testing suite
Config/         App configuration and capabilities
Firebase/       Firestore rules and administrator tooling
Simulation/     Simulator support utilities
```
