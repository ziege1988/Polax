import XCTest
@testable import Polux

/// Prüft die Bildregeln mit typischen Fällen – damit Anpassungen nichts Bestehendes kaputt machen.
final class FilterTests: XCTestCase {

    // MARK: Hilfen

    private func candidate(_ title: String = "", tags: [String] = [], source: SourceKind = .openverse) -> PhotoCandidate {
        let url = URL(string: "https://example.com/a.jpg")!
        return PhotoCandidate(id: UUID().uuidString, source: source, origin: "test", title: title, author: "",
                              imageURL: url, fallbackImageURL: nil, thumbURL: url, pageURL: nil,
                              tags: tags, query: nil)
    }

    private func collection(keywords: [String] = [], excluded: [String] = [],
                            subject: SubjectFocus = .any, requirePeople: Bool = true) -> PhotoCollection {
        var c = PhotoCollection(name: "Test", keywords: keywords, excludedWords: excluded)
        c.subject = subject
        c.requirePeople = requirePeople
        return c
    }

    // MARK: Schlagwörter

    func testFuzzyWords() {
        XCTAssertTrue(StyleEngine.fuzzyEqual("goth", "gothic"))
        XCTAssertTrue(StyleEngine.fuzzyEqual("portrait", "portraits"))
        XCTAssertTrue(StyleEngine.fuzzyEqual("editorial", "editoral"))      // Tippfehler
        XCTAssertFalse(StyleEngine.fuzzyEqual("man", "woman"))
        XCTAssertFalse(StyleEngine.fuzzyEqual("art", "artist"))
    }

    func testKeywordMatchesWithOneSpecificWord() {
        let c = collection(keywords: ["editorial gothic"])
        let hit = candidate("Gothic fashion shoot", tags: ["gothic", "fashion", "model"])
        XCTAssertGreaterThanOrEqual(StyleEngine.keywordMatch(hit, analysis: nil, collection: c), StyleEngine.keywordThreshold)
        XCTAssertNil(StyleEngine.exclusionReason(hit, collection: c))
    }

    func testGenericWordAloneIsNotEnough() {
        let c = collection(keywords: ["dark fine art portrait"])
        let miss = candidate("Dark night city", tags: ["dark", "night", "city", "art"])
        XCTAssertLessThan(StyleEngine.keywordMatch(miss, analysis: nil, collection: c), StyleEngine.keywordThreshold)
    }

    func testCandidateWithoutDescriptionIsRejected() {
        let c = collection(keywords: ["editorial gothic"])
        XCTAssertEqual(StyleEngine.exclusionReason(candidate(), collection: c), FilterReason.keyword)
    }

    func testPinterestBoardsSkipKeywordFilter() {
        let c = collection(keywords: ["editorial gothic"])
        XCTAssertNil(StyleEngine.exclusionReason(candidate("Pin", tags: ["portrait"], source: .rss), collection: c))
    }

    // MARK: Ausschlusswörter

    func testExcludedWordIsWholeWord() {
        let c = collection(keywords: ["portrait"], excluded: ["man"])
        XCTAssertTrue(StyleEngine.matchesExcludedWords(candidate(tags: ["man", "portrait"]), analysis: nil, collection: c))
        XCTAssertFalse(StyleEngine.matchesExcludedWords(candidate(tags: ["woman", "portrait"]), analysis: nil, collection: c))
    }

    func testExcludedPhrase() {
        let c = collection(keywords: ["portrait"], excluded: ["red carpet"])
        XCTAssertTrue(StyleEngine.matchesExcludedWords(candidate("Red carpet portrait"), analysis: nil, collection: c))
    }

    // MARK: Kunst statt Foto

    func testOldMasterPaintingIsRejected() {
        XCTAssertNotNil(StyleEngine.artReason(candidate("Vision of Tondal", tags: ["altarpiece", "bosch"])))
        XCTAssertNotNil(StyleEngine.artReason(candidate("Portrait, oil on canvas")))
    }

    func testAnimeAndStillLifeAreRejected() {
        XCTAssertEqual(StyleEngine.artReason(candidate(tags: ["anime", "girl"])), FilterReason.anime)
        XCTAssertEqual(StyleEngine.artReason(candidate("Still life with apples")), FilterReason.painting)
    }

    func testDigitalArtNeedsPhotorealism() {
        XCTAssertEqual(StyleEngine.artReason(candidate(tags: ["digitalart", "fantasyart", "portrait"])), FilterReason.digitalArt)
        XCTAssertNil(StyleEngine.artReason(candidate("Digital art portrait, photorealistic", tags: ["photorealistic"])))
    }

    func testPhotographyTermsStayAllowed() {
        // Typische Begriffe aus Fine-Art-, Akt- und Hochzeitsfotografie dürfen nicht sperren.
        let ok = [
            candidate("Rembrandt lighting portrait", tags: ["rembrandt", "lowkey"]),
            candidate("Caravaggio inspired nude", tags: ["caravaggio", "nude", "chiaroscuro"]),
            candidate("Wedding at the altar", tags: ["wedding", "altar", "church", "bride"]),
            candidate("Medieval dress", tags: ["medieval", "dress", "model"]),
            candidate("Dark fantasy shoot", tags: ["fantasy", "gown", "crown"]),
            candidate("Gold body paint", tags: ["bodypaint", "gold", "nude"]),
            candidate("Deer skull mask", tags: ["skull", "antlers", "mask", "tattoo"])
        ]
        for c in ok { XCTAssertNil(StyleEngine.artReason(c), "fälschlich gesperrt: \(c.title)") }
    }

    // MARK: Personen

    func testArchitectureWithoutPeopleIsRejected() {
        let c = collection(keywords: [])
        XCTAssertEqual(StyleEngine.exclusionReason(candidate(tags: ["architecture", "palace", "night"]), collection: c),
                       FilterReason.place)
    }

    func testWeddingInFrontOfCastleIsAllowed() {
        let c = collection(keywords: [])
        XCTAssertNil(StyleEngine.exclusionReason(candidate(tags: ["wedding", "castle", "couple"]), collection: c))
    }

    func testWrongSubject() {
        let c = collection(keywords: [], subject: .female)
        XCTAssertEqual(StyleEngine.exclusionReason(candidate(tags: ["man", "beard", "portrait"]), collection: c),
                       FilterReason.wrongSubject)
        XCTAssertNil(StyleEngine.exclusionReason(candidate(tags: ["woman", "portrait"]), collection: c))
    }

    func testImageWithoutPersonIsRejected() {
        let c = collection(keywords: [])
        let empty = ImageAnalysis(labels: ["building"], featurePrint: nil, luminance: 0.2, saturation: 0.2, personCount: 0)
        XCTAssertTrue(StyleEngine.lacksPeople(empty, collection: c))
        let detail = ImageAnalysis(labels: ["hand", "wedding"], featurePrint: nil, luminance: 0.4, saturation: 0.2, personCount: 0)
        XCTAssertFalse(StyleEngine.lacksPeople(detail, collection: c), "Detailaufnahme (Hände) muss erlaubt sein")
    }

    func testTextAndBannerImagesAreRejected() {
        let poster = ImageAnalysis(labels: [], featurePrint: nil, luminance: 0.5, saturation: 0.3, textCoverage: 0.2, aspect: 0.7)
        XCTAssertTrue(StyleEngine.looksLikeNonPhoto(poster))
        let banner = ImageAnalysis(labels: [], featurePrint: nil, luminance: 0.5, saturation: 0.3, textCoverage: 0, aspect: 3.0)
        XCTAssertTrue(StyleEngine.looksLikeNonPhoto(banner))
        let photo = ImageAnalysis(labels: [], featurePrint: nil, luminance: 0.3, saturation: 0.2, textCoverage: 0.01, aspect: 0.8)
        XCTAssertFalse(StyleEngine.looksLikeNonPhoto(photo))
    }

    // MARK: Suche

    func testQueriesUseOnlyOwnKeywords() {
        var c = collection(keywords: ["editorial gothic", "veil portrait"])
        c.subject = .female
        let qs = StyleEngine.queries(for: c, profile: StyleProfile(learnedTerms: ["sunset"]), count: 2)
        for q in qs {
            XCTAssertFalse(q.contains("sunset"), "gelernter Begriff darf nicht angehängt werden")
            XCTAssertTrue(q.hasPrefix("editorial gothic") || q.hasPrefix("veil portrait"))
            XCTAssertTrue(q.contains("woman"))
        }
    }
}

/// Pinterest-Adressen und Versionsvergleich.
final class PinterestAndUpdateTests: XCTestCase {
    func testBoardURLs() {
        XCTAssertEqual(RSSProvider.normalizedFeedURL("https://www.pinterest.de/nutzer/dark-art/")?.absoluteString,
                       "https://www.pinterest.com/nutzer/dark-art.rss")
        XCTAssertEqual(RSSProvider.normalizedFeedURL("de.pinterest.com/nutzer/dark-art/abschnitt/")?.absoluteString,
                       "https://www.pinterest.com/nutzer/dark-art.rss")
        XCTAssertEqual(RSSProvider.normalizedFeedURL("pinterest.com/nutzer")?.absoluteString,
                       "https://www.pinterest.com/nutzer/feed.rss")
        XCTAssertEqual(RSSProvider.normalizedFeedURL("https://www.pinterest.com/nutzer/board.rss")?.absoluteString,
                       "https://www.pinterest.com/nutzer/board.rss")
    }

    func testSinglePinIsNotABoard() {
        XCTAssertNil(RSSProvider.normalizedFeedURL("https://de.pinterest.com/pin/769473877824370611/"))
    }

    func testOtherFeedsUnchanged() {
        XCTAssertEqual(RSSProvider.normalizedFeedURL("https://example.tumblr.com/rss")?.absoluteString,
                       "https://example.tumblr.com/rss")
    }

    func testVersionCompare() {
        XCTAssertTrue(UpdateChecker.isVersion("1.0.10", newerThan: "1.0.9"))
        XCTAssertFalse(UpdateChecker.isVersion("1.0.9", newerThan: "1.0.10"))
        XCTAssertFalse(UpdateChecker.isVersion("1.0.16", newerThan: "1.0.16"))
    }

    func testDeviantArtCredentialsAreCleaned() {
        XCTAssertEqual(DeviantArtAuth.clean(" 12345 \n", digitsOnly: true), "12345")
        XCTAssertEqual(DeviantArtAuth.clean("client_id: 12345", digitsOnly: true), "12345")
        XCTAssertEqual(DeviantArtAuth.clean("abcdef0123456789abcdef0123456789\n", digitsOnly: false),
                       "abcdef0123456789abcdef0123456789")
        XCTAssertEqual(DeviantArtAuth.clean("client_secret: \"abc123\"", digitsOnly: false), "abc123")
    }

    // MARK: Ablehnungen

    @MainActor
    func testRejectionDoesNotPenalizeOwnKeywordsOrPeople() {
        let c = PhotoCollection(name: "Test", keywords: ["experimental nude"])
        let terms = LibraryStore.rejectableTerms(["experimental", "nude", "woman", "neon", "graffiti"], in: c)
        XCTAssertFalse(terms.contains("experimental"))
        XCTAssertFalse(terms.contains("nude"))
        XCTAssertFalse(terms.contains("woman"))
        XCTAssertTrue(terms.contains("graffiti"))
    }

    func testExperimentalNudeTaggedCountsAsPerson() {
        let c = PhotoCollection(name: "Test", keywords: ["experimental nude"])
        let cand = PhotoCandidate(id: "x", source: .deviantart, origin: "deviantart", title: "Untitled",
                                  author: "a", imageURL: URL(string: "https://example.com/a.jpg")!,
                                  fallbackImageURL: nil, thumbURL: URL(string: "https://example.com/a.jpg")!,
                                  pageURL: nil, tags: ["experimental nude"], query: "experimental nude")
        let empty = ImageAnalysis(labels: [], featurePrint: nil, luminance: 0.2, saturation: 0.2, personCount: 0)
        XCTAssertFalse(StyleEngine.lacksPeople(empty, collection: c, candidate: cand))
    }
}
