# Releases

One manifest per APK or AAB built with `dart run tool/build_release.dart` (see the main README): the commit that
produced it, versions, build time, Flutter version, signing, the dart-define keys and the file's SHA-256. The APKs and
AABs themselves are not versioned; a file is the release if its SHA-256 matches its manifest here. When a Play AAB and
a QA APK come from the same commit, the AAB keeps `<name>.json` and the APK's manifest is `<name>.apk.json`.

| File | Commit | SHA-256 | Signing | Field test |
|---|---|---|---|---|
| blow-nights-1.0.1+2-3b74b7a.apk | 3b74b7a | d9fccc8e…ea439 | debug keys | deferred until ticketing launches (NFC is only used by the staff scanners) |
| blow-nights-1.0.2+3-fe1ff9f.apk | fe1ff9f | 6ef03513…15ccd | debug keys | superseded by 1.0.3+4 before its field test (1.0.3+4 contains it) |
| blow-nights-1.0.3+4-a2e6de5.apk | a2e6de5 | e252aa91…57e23 | debug keys | superseded by 1.0.6+7 before its field test (1.0.6+7 contains it) |
| blow-nights-1.0.4+5-b7db72a.aab | b7db72a | ead57931…628a5 | upload key (Play) | never uploaded: still sold digital goods through Stripe (Play payments policy); superseded by 1.0.5+6 |
| blow-nights-1.0.5+6-1f4b2c2.aab | 1f4b2c2 | d08c5991…1c3bc | upload key (Play) | never uploaded: superseded by 1.0.6+7 (package updates) |
| blow-nights-1.0.6+7-8b9586e.aab | 8b9586e | 84de0fed…0032a | upload key (Play) | pending: Play Console internal testing track (also checks Play Integrity / App Check) |
| blow-nights-1.0.6+7-8b9586e.apk | 8b9586e | 9a8e3e43…0a052 | debug keys | pending: reference venues (badge, notice, claim with document photo, Mis reclamaciones) and «Horario no disponible» on the city home, on a phone (installs over 1.0.3+4: same debug key) |
| blow-nights-1.0.7+8-ecc0a85.aab | ecc0a85 | 5faa420c…6229b | upload key (Play) | pending: Play Console internal testing track (location privacy: the radar stores a ~200 m position, never the GPS fix) |
| blow-nights-1.0.8+9-dd9f6c1.aab | dd9f6c1 | f88937ea…c9cc8 | upload key (Play) | pending: internal testing track, then Google Play purchases with license testers once Play Console is set up (blow-nights-app docs/PLAY_BILLING.md); moduleAppPremium stays off until then. Built from the branch of #18; its tree is identical to main b53804c (the merge) |
| blow-nights-1.0.10+11-0048fac.aab | 0048fac | b7727c01…1d0aa | upload key (Play) | pending: internal testing track. Replaces 1.0.8+9: only the dynamic QR (no PIN, no static code, no simulated menu, #20) and the venues' free month (#21, #22). Google Play purchases with license testers once Play Console is set up; moduleAppPremium stays off until then |
| blow-nights-1.0.11+12-e2f8f2d.aab | e2f8f2d | 14b326ac…9d8e4 | upload key (Play) | pending: internal testing track. Replaces 1.0.10+11 (never uploaded): adds #25, the investors screen without download buttons for the round's documents (removed from the web, blow-nights-app #190). Built from the branch of #26; its tree is identical to main fb8783b (the merge) |
