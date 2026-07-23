package wtf.ebtl.app

import io.flutter.embedding.android.FlutterFragmentActivity

// flutter_stripe requires the host Activity to extend FlutterFragmentActivity so
// the native Payment Sheet can be presented from a FragmentActivity context.
class MainActivity : FlutterFragmentActivity()
