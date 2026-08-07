/// Global app state singleton.
/// This is separated from main.dart to avoid circular imports.
library;

import 'app_state.dart';

AppState? _instance;

AppState get appState {
  if (_instance == null) throw StateError('AppState not initialized. Call initAppState() first.');
  return _instance!;
}

void setAppState(AppState state) => _instance = state;
