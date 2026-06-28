Run set -o pipefail
? Clean Succeeded
? Processing empty-GRDB_GRDB.plist
? Copying /Users/runner/work/hiking/hiking/front/build/Build/Products/Release-iphoneos/GRDB_GRDB.bundle/PrivacyInfo.xcprivacy
? Touching GRDB_GRDB.bundle (in target 'GRDB_GRDB' from project 'GRDB')
? Linking CoreGPX.o
? Linking GRDB.o
? Copying /Users/runner/work/hiking/hiking/front/build/Build/Products/Release-iphoneos/Hiking.app/glyphs
? Copying /Users/runner/work/hiking/hiking/front/build/Build/Products/Release-iphoneos/Hiking.app/PrivacyInfo.xcprivacy
? Processing Info.plist
    The application supports opening files, but doesn't declare whether it supports opening them in place. You can add an LSSupportsOpeningDocumentsInPlace entry or an UISupportsDocumentBrowser entry to your Info.plist to declare support. (in target 'Hiking' from project 'Hiking')

??  /Users/runner/work/hiking/hiking/front/Sources/Core/Map/MapController.swift:43:11: 'setVisibleCoordinateBounds(_:edgePadding:animated:)' is deprecated: Use `-setVisibleCoordinateBounds:edgePadding:animated:completionHandler:` instead.

        m.setVisibleCoordinateBounds(bounds,
          ^



??  /Users/runner/work/hiking/hiking/front/Sources/Core/Map/MapController.swift:60:11: 'setVisibleCoordinateBounds(_:edgePadding:animated:)' is deprecated: Use `-setVisibleCoordinateBounds:edgePadding:animated:completionHandler:` instead.

        m.setVisibleCoordinateBounds(bounds,
          ^



??  /Users/runner/work/hiking/hiking/front/Sources/Core/Map/MapLibreView.swift:618:17: 'setVisibleCoordinateBounds(_:edgePadding:animated:)' is deprecated: Use `-setVisibleCoordinateBounds:edgePadding:animated:completionHandler:` instead.

            map.setVisibleCoordinateBounds(bounds,
                ^



?  /Users/runner/work/hiking/hiking/front/Sources/Features/Map/MapScreen.swift:206:42: cannot find 'WaypointEditSheet' in scope

        .sheet(item: $editingPOI) { w in WaypointEditSheet(waypoint: w) { loadPOIs() } }
                                         ^~~~~~~~~~~~~~~~~



?  /Users/runner/work/hiking/hiking/front/Sources/Features/Map/MapScreen.swift:344:62: value of type 'TrackRepository' has no member 'independentWaypoints'

    private func loadPOIs() { pois = (try? TrackRepository().independentWaypoints()) ?? [] }
                                           ~~~~~~~~~~~~~~~~~ ^~~~~~~~~~~~~~~~~~~~



??  /Users/runner/work/hiking/hiking/front/Sources/Features/Me/OfflineMapsView.swift:91:17: result of 'try?' is unused

                try? OfflineMaps.importPack(from: url)
                ^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~



??  /Users/runner/work/hiking/hiking/front/Sources/Core/Navigation/SpeechAnnouncer.swift:7:17: stored property 'synth' of 'Sendable'-conforming class 'SpeechAnnouncer' has non-Sendable type 'AVSpeechSynthesizer'

    private let synth = AVSpeechSynthesizer()
                ^



??  /Users/runner/work/hiking/hiking/front/Sources/Features/Tracks/TracksView.swift:359:9: result of 'try?' is unused

        try? repo.createFolder(name: name); reload()
           ^


Swift 编译错误（从完整日志提取）
  737:/Users/runner/work/hiking/hiking/front/Sources/Features/Map/MapScreen.swift:206:42: error: cannot find 'WaypointEditSheet' in scope
  740:/Users/runner/work/hiking/hiking/front/Sources/Features/Map/MapScreen.swift:68:44: error: extra argument 'onWaypointSelect' in call
  742:/Users/runner/work/hiking/hiking/front/Sources/Features/Map/MapScreen.swift:344:62: error: value of type 'TrackRepository' has no member 'independentWaypoints'
Error: Process completed with exit code 1.