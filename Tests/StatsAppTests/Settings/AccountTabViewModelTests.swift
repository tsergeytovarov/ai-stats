import XCTest
import GRDB
@testable import StatsApp

@MainActor
final class AccountTabViewModelTests: XCTestCase {
    var dbq: DatabaseQueue!
    var client: AiuseAPIClient!
    var keychain: MemoryKeychainStore!
    var secretBox: SecretBox!
    var vm: AccountTabViewModel!

    override func setUpWithError() throws {
        dbq = try DatabaseQueue()
        try Database.migrate(dbq)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        keychain = MemoryKeychainStore()
        secretBox = SecretBox()
        secretBox.value = "test-secret"
        client = AiuseAPIClient(
            baseURL: URL(string: "https://test.local/api")!,
            secretProvider: { [secretBox] in secretBox?.value },
            session: session
        )
        vm = AccountTabViewModel(api: client, keychain: keychain, secretBox: secretBox, db: dbq)
        MockURLProtocol.responder = nil
        MockURLProtocol.lastRequest = nil
        MockURLProtocol.lastBody = nil
    }

    func test_createAccount_withAvatar_persistsBlobLocally() async throws {
        MockURLProtocol.responder = { _ in
            let resp = HTTPURLResponse(
                url: URL(string: "https://test.local/api/profiles")!,
                statusCode: 201, httpVersion: "HTTP/1.1", headerFields: nil)!
            let json = #"{"friend_code":"XK7P3M9Q2A","api_secret":"newsecret","server_user_id":42}"#
            return (resp, json.data(using: .utf8)!)
        }
        let blob = Data([0xFF, 0xD8, 0xFF, 0xE0])  // JPEG

        await vm.createAccount(displayName: "Я", avatar: blob, avatarMime: "image/jpeg")

        XCTAssertNil(vm.errorMessage)
        let stored = try await dbq.read { try StatsQueries.loadMyProfile($0) }
        XCTAssertEqual(stored?.avatarBlob, blob)
        XCTAssertEqual(stored?.avatarMime, "image/jpeg")
        XCTAssertNil(stored?.avatarEtag)  // ETag получим позже через GET /avatars
    }

    func test_updateAvatar_callsPatchAndUpdatesLocalBlob() async throws {
        // существующий профиль без аватарки
        try await dbq.write { db in
            let row = MyProfileRow(
                id: 1,
                friendCode: "XK7P3M9Q2A",
                displayName: "Я",
                avatarPath: nil,
                sharingEnabled: true,
                serverUserId: 42
            )
            try StatsQueries.saveMyProfile(db, row)
        }
        await vm.reload()
        guard case .created = vm.state else {
            XCTFail("expected created state, got \(vm.state)")
            return
        }

        MockURLProtocol.responder = { _ in
            let resp = HTTPURLResponse(
                url: URL(string: "https://test.local/api/profiles/me")!,
                statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            let json = #"{"friend_code":"XK7P3M9Q2A","display_name":"Я","sharing_enabled":true,"created_at":"2026-05-24T10:00:00Z"}"#
            return (resp, json.data(using: .utf8)!)
        }
        let blob = Data([0x89, 0x50, 0x4E, 0x47])  // PNG

        await vm.updateAvatar(blob, mime: "image/png")

        XCTAssertNil(vm.errorMessage)
        // PATCH /profiles/me с Bearer
        let req = MockURLProtocol.lastRequest
        XCTAssertEqual(req?.httpMethod, "PATCH")
        XCTAssertEqual(req?.url?.path, "/api/profiles/me")
        XCTAssertEqual(req?.value(forHTTPHeaderField: "Authorization"), "Bearer test-secret")

        // body содержит avatar_b64
        let body = try XCTUnwrap(MockURLProtocol.lastBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["avatar_b64"] as? String, blob.base64EncodedString())
        XCTAssertEqual(json?["avatar_mime"] as? String, "image/png")

        // локально blob сохранён
        let stored = try await dbq.read { try StatsQueries.loadMyProfile($0) }
        XCTAssertEqual(stored?.avatarBlob, blob)
        XCTAssertEqual(stored?.avatarMime, "image/png")

        // state тоже обновлён
        if case let .created(profile) = vm.state {
            XCTAssertEqual(profile.avatarBlob, blob)
        } else {
            XCTFail("expected created state with updated blob")
        }
    }

    func test_updateAvatar_apiError_keepsLocalUnchanged_andSetsError() async throws {
        let initialBlob = Data([0xFF, 0xD8])
        try await dbq.write { db in
            let row = MyProfileRow(
                id: 1,
                friendCode: "XK7P3M9Q2A",
                displayName: "Я",
                avatarPath: nil,
                sharingEnabled: true,
                serverUserId: 42,
                avatarBlob: initialBlob,
                avatarMime: "image/jpeg",
                avatarEtag: "v1"
            )
            try StatsQueries.saveMyProfile(db, row)
        }
        await vm.reload()

        MockURLProtocol.responder = { _ in
            let resp = HTTPURLResponse(
                url: URL(string: "https://test.local/api/profiles/me")!,
                statusCode: 413, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (resp, Data("payload too large".utf8))
        }

        await vm.updateAvatar(Data([0x00, 0x01, 0x02]), mime: "image/png")

        XCTAssertNotNil(vm.errorMessage)
        // Локально blob НЕ затёрт (сначала PATCH, потом запись — PATCH провалился)
        let stored = try await dbq.read { try StatsQueries.loadMyProfile($0) }
        XCTAssertEqual(stored?.avatarBlob, initialBlob)
        XCTAssertEqual(stored?.avatarEtag, "v1")
    }
}
