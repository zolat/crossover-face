import Toybox.Lang;

//! Sideload version shown by the on-watch settings menu.
//!
//! Garmin does not expose the manifest version to a running app, so this value
//! is intentionally explicit and must be bumped for every watch test build.
//! Keep it equal to the application version in manifest.xml.
module BuildInfo {
    const VERSION = "0.1.0";
}
