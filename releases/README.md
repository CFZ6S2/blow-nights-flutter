# Releases

One manifest per APK built with `dart run tool/build_release.dart` (see the main README): the commit that produced
it, versions, build time, Flutter version, signing, the dart-define keys and the APK's SHA-256. The APKs themselves
are not versioned; a file is the release if its SHA-256 matches its manifest here.

| APK | Commit | SHA-256 | Signing | Field test |
|---|---|---|---|---|
| blow-nights-1.0.1+2-3b74b7a.apk | 3b74b7a | d9fccc8e…ea439 | debug keys | deferred until ticketing launches (NFC is only used by the staff scanners) |
| blow-nights-1.0.2+3-fe1ff9f.apk | fe1ff9f | 6ef03513…15ccd | debug keys | superseded by 1.0.3+4 before its field test (1.0.3+4 contains it) |
| blow-nights-1.0.3+4-a2e6de5.apk | a2e6de5 | e252aa91…57e23 | debug keys | pending: reference venues (badge, notice, claim with document photo, Mis reclamaciones) and «Horario no disponible» on the city home, on a phone |
