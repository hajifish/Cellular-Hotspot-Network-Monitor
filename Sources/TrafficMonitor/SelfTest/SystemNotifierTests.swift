enum SystemNotifierTests {
    static func all() {
        postRoutesThroughDeliverSeam()
        postForwardsOnFailureThroughSeam()
        activationRouterReceivesIdentifier()
        repeatedConfigureReplacesRouter()
    }

    static func postRoutesThroughDeliverSeam() {
        let original = SystemNotifier.deliver
        defer { SystemNotifier.deliver = original }
        var posted: [(title: String, body: String, identifier: String, sound: Bool,
                      onFailure: ((Error) -> Void)?)] = []
        SystemNotifier.deliver = { title, body, identifier, sound, onFailure in
            posted.append((title, body, identifier, sound, onFailure))
        }
        SystemNotifier.post(title: "标题", body: "正文", identifier: "id-1", sound: false)
        TestRun.expectEqual(posted.count, 1, "post 经 seam 投递一次")
        if posted.count == 1 {
            let p = posted[0]
            TestRun.expectEqual(p.title, "标题", "title 透传")
            TestRun.expectEqual(p.body, "正文", "body 透传")
            TestRun.expectEqual(p.identifier, "id-1", "identifier 透传")
            TestRun.expectEqual(p.sound, false, "sound 透传")
            TestRun.expect(p.onFailure == nil, "默认无 onFailure")
        }
    }

    /// 经 seam 模拟默认实现的投递失败路径：post 收到的 onFailure 被回调、错误对象透传。
    /// 默认实现本体（UN add 回调 + 主线程派发）依赖 UN center，裸二进制抛异常无法自测，GUI 目检覆盖。
    static func postForwardsOnFailureThroughSeam() {
        let original = SystemNotifier.deliver
        defer { SystemNotifier.deliver = original }
        var failures: [Error] = []
        SystemNotifier.deliver = { _, _, _, _, onFailure in
            onFailure?(DeliverError.failed)
        }
        SystemNotifier.post(title: "标题", body: "正文", identifier: "id-2",
                            onFailure: { failures.append($0) })
        TestRun.expectEqual(failures.count, 1, "投递失败经 onFailure 回调")
        if failures.count == 1 {
            TestRun.expectEqual(String(describing: failures[0]),
                                String(describing: DeliverError.failed), "错误对象透传")
        }
    }

    private enum DeliverError: Error { case failed }

    /// 裸二进制（无 bundle）里 configureActivation 只注册路由、跳过 UN center 接线；
    /// 本用例跑通本身就是「未接线」的证明（真接线会因访问 UN center 抛异常）
    static func activationRouterReceivesIdentifier() {
        var received: [String] = []
        SystemNotifier.configureActivation { received.append($0) }
        SystemNotifier.handleActivation(identifier: "update-v9.9.9")
        TestRun.expectEqual(received, ["update-v9.9.9"], "点击路由透传 identifier")
    }

    static func repeatedConfigureReplacesRouter() {
        var received: [String] = []
        SystemNotifier.configureActivation { received.append("old-" + $0) }
        SystemNotifier.configureActivation { received.append("new-" + $0) }
        SystemNotifier.handleActivation(identifier: "id-3")
        TestRun.expectEqual(received, ["new-id-3"], "重复 configure 用最新路由替换")
    }
}
