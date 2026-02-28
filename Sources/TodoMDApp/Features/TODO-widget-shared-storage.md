# TODO: Widget Shared Storage

## Goal
Use the exact same configured task folder in app + widget by moving folder settings to shared storage.

## Tasks
- Add an App Group capability to `TodoMDApp` and `TodoMDWidgets`.
- Define a single App Group identifier constant used by both targets.
- Move folder preference reads/writes to `UserDefaults(suiteName:)` for that App Group.
- Migrate existing non-shared defaults (`settings_notes_folder_*`, `settings_icloud_folder_name`) into App Group defaults on first launch.
- Update widget code paths to use only shared folder settings (remove folder auto-detection fallback once migration is complete).
- Add tests for migration and shared-default resolution behavior.
