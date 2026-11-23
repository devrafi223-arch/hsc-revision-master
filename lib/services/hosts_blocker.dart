// Website blocking via the hosts file, desktop only.
//
// The real implementation lives in hosts_blocker_io.dart (dart:io);
// on web this resolves to the no-op stub, so the web build keeps
// compiling. All methods are safe to call anywhere.
export 'hosts_blocker_stub.dart'
    if (dart.library.io) 'hosts_blocker_io.dart';
