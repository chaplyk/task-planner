# Privacy Policy for NagadAI

**Last updated:** November 17, 2026

This privacy policy explains how NagadAI ("the App", "we", "us") collects, uses, and protects your information. NagadAI is developed and maintained by an individual developer. If you have questions, contact us at **nagadai@chaplyk.com**.

## Information We Collect

### Account Information
When you sign in with Google, we collect your Google account's email address, display name, and profile photo (if available) to create and manage your account via Firebase Authentication. If you continue as a guest, an anonymous account is created instead and no email address or name is collected.

### Reminders and Related Content
To provide the App's core functionality, we store the reminders you create, including:
- The reminder text and summary
- Scheduled times and conditions you specify
- Categories and lists you assign or that are automatically suggested
- Voice transcripts of reminders you create by speaking, and the recognized text derived from them

This data is stored in our cloud database (Google Firebase/Firestore) and is associated with your account so it can sync across your devices.

### Microphone Audio
If you use voice input to create reminders, the App accesses your device's microphone to convert speech to text. Speech recognition is performed on-device using Google's ML Kit. Audio is not stored by the App; only the resulting text transcript is saved as part of your reminder, as described above.

### Location Data
Location is used only for place-based reminders, and only if you grant the location permission.

- **Saved places.** When you save a place, we store the name you give it together with either its GPS coordinates or the name of the Wi-Fi network you are connected to. This is stored in our cloud database with your account.
- **Background location.** To remind you when you arrive at or leave a saved place or a kind of store (for example "at the grocery store"), the App accesses your location in the background, including when the App is closed or not in use. Saved GPS places are watched with on-device geofences. Wi-Fi places are detected by reading the name of the network your phone is connected to.
- **Nearby store lookups.** Only while you have an open reminder tied to a kind of store, the App sends your current coordinates to Geoapify when you have moved at least 150 m since the last lookup (checked about every 10 minutes) to find the stores of that kind within about 1.5 km. When you stay near one of them, the App may also ask Geoapify for that store's building outline, using the store's ID. Requests contain the coordinates, a search radius and the kinds of store. They do not contain your account, name or reminders. At most 100 lookups are made per day. The list of nearby stores and the GPS checks that confirm a visit stay on your device.
- **Phone calendar (optional).** If you turn on "Sync with phone calendar" in Settings, the App asks for calendar access and adds your timed reminders (their text and times) to a "NagadAI" calendar on your phone. It doesn't read your other calendars or events and sends nothing anywhere itself. Turning the option off, or signing out, deletes the NagadAI calendar from your phone.

Your location history is not stored: apart from the saved places above, positions are used on the device and discarded.

### Physical Activity Data
The App requests access to your device's activity recognition sensors (e.g., walking, driving, running) to support activity-based reminders (for example, reminding you of something the next time you start driving). This data is processed on-device and is not shared with third parties. Only the activity condition you configure is stored with your reminder.

### Notifications
The App uses local device notifications and a foreground service to schedule and deliver reminders at the correct time or in response to detected activity or location. This processing happens on your device.

### AI Processing of Reminder Text
The text of a reminder (typed, or transcribed from your voice) is turned into a structured reminder by an AI model. Together with the text, the App sends the names of your categories, lists and saved places so the model can pick among them.

- **Cloud model (default).** The text is sent to Google's Gemini models through Firebase AI Logic. With this option, text you type may be sent while you are still typing, in order to show suggestions. Category names are also sent to Gemini to suggest an emoji.
- **On-device model (optional).** If you choose the on-device model in Settings, reminder text is processed on your phone and is not sent to Gemini. Until the model has finished downloading, the cloud model is used.

### Usage, Diagnostics and Performance Data
The App uses Google Firebase services that collect data automatically:

- **Firebase Analytics** records app usage events, such as signing in, starting a voice recording, and creating a reminder (with how it was created and its trigger type, not its text), along with device and app information.
- **Firebase Crashlytics** collects crash and error reports. These do not include the text of your reminders.
- **Firebase Performance Monitoring** measures how long operations take.
- **Firebase App Check** (using Google Play Integrity) verifies that requests come from a genuine copy of the App.

## How We Use Your Information

We use the information described above solely to:
- Operate and improve the App's core reminder functionality
- Authenticate your account and sync your data across your devices
- Schedule and deliver notifications for your reminders
- Understand and categorize your reminders using AI, in the cloud or on your device as described above
- Deliver place-based reminders using your location
- Diagnose errors and understand how the App is used so it can be improved

We do not sell your personal information, and we do not use your data for advertising.

## Data Sharing

We do not sell your personal information and do not share it with advertisers. Your data is shared only with the following service providers, to the extent needed to run the App:

- **Google** — Firebase Authentication and Firestore (account and reminder data), Gemini via Firebase AI Logic (reminder text, when the cloud model is used), Firebase Analytics, Crashlytics, Performance Monitoring and App Check, subject to [Google's Privacy Policy](https://policies.google.com/privacy).
- **Geoapify** (Geoapify GmbH, Germany): receives your current coordinates (and, like any server, your IP address) for the nearby store lookups described above. When you add a place on the map, it also receives the map area you are viewing (to show the map), the coordinates of the pin (to show its address) and any text you type into the place search (with the map's position, to rank the suggestions).

## Data Retention and Deletion

Your reminders and account data are retained as long as your account is active. You can delete individual reminders within the App at any time. You can permanently delete your account and associated data from the Settings screen in the App ("Delete account"). This deletes your reminders, lists, categories and saved places from our database, removes your account, and signs you out of the App. Guest accounts and their data cannot be recovered after the App is uninstalled.

Analytics, crash and performance data is retained by Google according to Firebase's retention periods and is not linked to your account by us.

## Children's Privacy

NagadAI is not directed at children under 13, and we do not knowingly collect personal information from children under 13.

## Security

We use industry-standard measures, including those provided by Firebase, to protect your information. However, no method of electronic storage or transmission is 100% secure.

## Changes to This Policy

We may update this privacy policy from time to time. Changes will be posted on this page with an updated "Last updated" date.

## Contact Us

If you have any questions about this privacy policy, please contact us at **nagadai@chaplyk.com**.
