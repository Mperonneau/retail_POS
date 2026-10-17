{{flutter_js}}
{{flutter_build_config}}

// No serviceWorkerSettings: Flutter's own worker would take over the "/"
// scope from asset_refresh_sw.js and then unregister itself.
_flutter.loader.load();
