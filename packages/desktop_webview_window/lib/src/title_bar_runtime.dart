// Set only by the primary isolate's entrypoint hook. A separate toolbar isolate
// runs that same entrypoint; the application's main/runApp contract is unchanged.
bool titleBarHookRegistered = false;
