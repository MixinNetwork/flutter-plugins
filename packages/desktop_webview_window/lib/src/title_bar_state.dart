// Set when the application calls the title-bar hook in its main isolate.
// The title-bar engine runs in a separate isolate, so this must be set even
// when the hook returns false for the application's normal startup arguments.
bool titleBarInitialized = false;
