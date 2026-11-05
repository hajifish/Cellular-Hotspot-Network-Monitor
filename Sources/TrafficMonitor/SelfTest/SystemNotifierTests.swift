enum SystemNotifierTests {
    static func all() {
        postRoutesThroughDeliverSeam()
        activationRouterReceivesIdentifier()
    }

    static func postRoutesThroughDeliverSeam() {
        let original = SystemNotifier.deliver
        defer { SystemNotifier.deliver = original }
        var posted: [(String, String, String, Bool)] = []
        SystemNotifier.deliver = { title, body, identifier, sound in
            posted.append((title, body, identifier, sound))
        }
        SystemNotifier.post(title: "标题", body: "正文", identifier: "id-1", sound: false)
        TestRun.expectEqual(posted.count, 1, "post 经 seam 投递一次")
        if posted.count == 1 {
            let p = posted[0]
            TestRun.expectEqual(p.0, "标题", "title 透传")
            TestRun.expectEqual(p.1, "正文", "body 透传")
            TestRun.expectEqual(p.2, "id-1", "identifier 透传")
            TestRun.expectEqual(p.3, false, "sound 透传")
        }
    }

    static func activationRouterReceivesIdentifier() {
        var received: [String] = []
        SystemNotifier.configureActivation { received.append($0) }
        SystemNotifier.handleActivation(identifier: "update-v9.9.9")
        TestRun.expectEqual(received, ["update-v9.9.9"], "点击路由透传 identifier")
    }
}
