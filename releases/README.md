# Releases

One manifest per APK built with `dart run tool/build_release.dart` (see the main README): the commit that produced
it, versions, build time, Flutter version, signing, the dart-define keys and the APK's SHA-256. The APKs themselves
are not versioned; a file is the release if its SHA-256 matches its manifest here.

| APK | Commit | SHA-256 | Signing | Field test |
|---|---|---|---|---|
| blow-nights-1.0.1+2-3b74b7a.apk | 3b74b7a | d9fccc8e…ea439 | debug keys | deferred until ticketing launches (NFC is only used by the staff scanners) |
