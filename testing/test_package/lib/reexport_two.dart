/// {@canonical-for reexport.somelib.SomeClass}
/// {@canonical-for reexport.somelib.AUnicornClass}
/// {@canonical-for something.ThatDoesntExist}
/// {@canonical-for reexport.somelib.DocumentThisExtensionOnce}
/// {@category Unreal}

library reexport_two;

// Intentionally create some duplicates via reexporting.
export 'src/mixins.dart' show MixedIn, AMixin;
export 'src/somelib.dart';
