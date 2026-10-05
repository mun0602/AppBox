//
//  MCRemoteAPI.swift
//  LiveContainer
//
//  mun container — Remote Control API
//  Lightweight HTTP server (Network.framework) to control mun container
//  remotely: list/launch/install apps, manage MunChanger profiles.
//
//  Security: every request must carry the token (X-Mun-Token header or
//  ?token= query). The token is generated on first enable and shown in
//  Settings. Traffic is plain HTTP — use on trusted networks or via
//  USB port forwarding (iproxy).
//

import Foundation
import Network
import UIKit

@_cdecl("MCMaybeStartRemoteAPI")
public func MCMaybeStartRemoteAPI() {
    if UserDefaults.standard.bool(forKey: MCRemoteAPI.enabledKey) {
        // prime the token cache NOW: bootstrap time is before guest mode swaps
        // the NSUserDefaults domain, later reads would see the guest's domain
        _ = MCRemoteAPI.shared.token
        MCRemoteAPI.shared.start()
    }
}

final class MCRemoteAPI: @unchecked Sendable {
    static let shared = MCRemoteAPI()

    static let enabledKey = "MCRemoteAPIEnabled"
    static let portKey = "MCRemoteAPIPort"
    static let tokenKey = "MCRemoteAPIToken"
    static let defaultPort: UInt16 = 8642

    private var listener: NWListener?
    private let stateQueue = DispatchQueue(label: "mun.remoteapi.state")
    private(set) var runningPort: UInt16 = 0
    private var connectionCounter = 0

    var isRunning: Bool { listener != nil }

    private var cachedToken: String?
    var token: String {
        stateQueue.sync {
            if let cached = cachedToken { return cached }
            if let t = UserDefaults.standard.string(forKey: Self.tokenKey), !t.isEmpty {
                cachedToken = t
                return t
            }
            let t = UUID().uuidString
            UserDefaults.standard.set(t, forKey: Self.tokenKey)
            cachedToken = t
            return t
        }
    }

    var configuredPort: UInt16 {
        let p = UserDefaults.standard.integer(forKey: Self.portKey)
        return (p >= 1024 && p <= 65535) ? UInt16(p) : Self.defaultPort
    }

    // MARK: - Lifecycle

    /// Returns error message on failure, nil on success.
    static func diag(_ msg: String) {
        let path = NSHomeDirectory() + "/Documents/mcapi.log"
        let line = Date().description + " " + msg + "\n"
        let fm = FileManager.default
        if let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile(); h.write(Data(line.utf8)); h.closeFile()
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    @discardableResult
    func start() -> String? {
        Self.diag("start() called, enabled=\(UserDefaults.standard.bool(forKey: Self.enabledKey)) port=\(UserDefaults.standard.integer(forKey: Self.portKey))")
        var result: String? = nil
        stateQueue.sync {
            if listener != nil { result = nil; return }
            let port = configuredPort
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                result = "Invalid port \(port)"
                return
            }
            do {
                let params = NWParameters.tcp
                params.allowLocalEndpointReuse = true
                let l = try NWListener(using: params, on: nwPort)
                l.newConnectionHandler = { [weak self] conn in
                    self?.handleConnection(conn)
                }
                l.stateUpdateHandler = { [weak self] state in
                    if case .failed(let err) = state {
                        NSLog("[mun-api] listener failed: \(err)")
                        Self.diag("listener failed: \(err)")
                        self?.stateQueue.async { self?.listener = nil }
                    }
                }
                listener = l
                runningPort = port
                l.start(queue: .global(qos: .utility))
                NSLog("[mun-api] listening on port \(port)")
                Self.diag("listening on port \(port)")
                result = nil
            } catch {
                Self.diag("bind failed: \(error.localizedDescription)")
                result = "Cannot bind port \(port): \(error.localizedDescription)"
            }
        }
        return result
    }

    func stop() {
        stateQueue.sync {
            listener?.cancel()
            listener = nil
            runningPort = 0
        }
    }

    func restartIfEnabled() {
        if UserDefaults.standard.bool(forKey: Self.enabledKey) {
            stop()
            if let err = start() {
                NSLog("[mun-api] autostart failed: \(err)")
            }
        }
    }

    // MARK: - HTTP plumbing

    private func handleConnection(_ conn: NWConnection) {
        conn.start(queue: .global(qos: .utility))
        readRequest(conn, buffer: Data())
    }

    private func readRequest(_ conn: NWConnection, buffer: Data) {
        recvSome(conn, accumulated: buffer) { data, closed in
            var buf = data
            if let range = buf.range(of: Data("\r\n\r\n".utf8)) {
                let headData = buf.subdata(in: buf.startIndex..<range.lowerBound)
                buf.removeSubrange(buf.startIndex..<range.upperBound)
                guard let head = String(data: headData, encoding: .utf8) else {
                    self.respond(conn, status: 400, body: ["error": "bad request"])
                    return
                }
                var lines = head.components(separatedBy: "\r\n")
                let requestLine = lines.removeFirst().components(separatedBy: " ")
                guard requestLine.count >= 2 else {
                    self.respond(conn, status: 400, body: ["error": "bad request line"])
                    return
                }
                let method = requestLine[0]
                let target = requestLine[1]
                var headers: [String: String] = [:]
                for line in lines {
                    if let idx = line.firstIndex(of: ":") {
                        let k = String(line[line.startIndex..<idx]).trimmingCharacters(in: .whitespaces).lowercased()
                        let v = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
                        headers[k] = v
                    }
                }
                let contentLength = Int(headers["content-length"] ?? "0") ?? 0
                self.readBody(conn, buf: buf, remaining: contentLength) { body in
                    self.route(conn, method: method, target: target, headers: headers, body: body)
                }
            } else if closed {
                conn.cancel()
            } else if buf.count > 1 << 20 {
                self.respond(conn, status: 413, body: ["error": "headers too large"])
            } else {
                self.readRequest(conn, buffer: buf)
            }
        }
    }

    private func readBody(_ conn: NWConnection, buf: Data, remaining: Int, done: @escaping (Data) -> Void) {
        if buf.count >= remaining {
            done(buf.prefix(remaining))
            return
        }
        recvSome(conn, accumulated: buf) { data, closed in
            if closed && data.count < remaining {
                done(data)
                return
            }
            self.readBody(conn, buf: data, remaining: remaining, done: done)
        }
    }

    private func recvSome(_ conn: NWConnection, accumulated: Data, onData: @escaping (Data, Bool) -> Void) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { data, _, isComplete, error in
            var buf = accumulated
            if let data, !data.isEmpty { buf.append(data) }
            let closed = isComplete || error != nil
            onData(buf, closed)
        }
    }

    private func respond(_ conn: NWConnection, status: Int, body: Any) {
        let json: Data
        if let s = body as? String {
            json = Data(s.utf8)
        } else if JSONSerialization.isValidJSONObject(body) {
            json = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data("{}".utf8)
        } else {
            json = Data("{}".utf8)
        }
        var head = "HTTP/1.1 \(status) \(statusText(status))\r\n"
        head += "Content-Type: application/json; charset=utf-8\r\n"
        head += "Content-Length: \(json.count)\r\n"
        head += "Connection: close\r\n\r\n"
        let payload = Data(head.utf8) + json
        conn.send(content: payload, completion: .contentProcessed { _ in
            conn.cancel()
        })
    }

    private func statusText(_ s: Int) -> String {
        switch s {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 413: return "Payload Too Large"
        case 500: return "Internal Server Error"
        default: return "Status"
        }
    }

    // MARK: - Routing

    private struct Route {
        let method: String
        let path: String
        let query: [String: String]
    }

    private func parseTarget(_ target: String) -> Route {
        var path = target
        var query: [String: String] = [:]
        if let idx = target.firstIndex(of: "?") {
            path = String(target[target.startIndex..<idx])
            let qs = String(target[target.index(after: idx)...])
            for pair in qs.components(separatedBy: "&") {
                let kv = pair.components(separatedBy: "=")
                if kv.count == 2 {
                    query[kv[0]] = kv[1].removingPercentEncoding ?? kv[1]
                }
            }
        }
        return Route(method: "", path: path, query: query)
    }

    private func route(_ conn: NWConnection, method: String, target: String, headers: [String: String], body: Data) {
        let r = parseTarget(target)
        let path = r.path

        // Token check
        let supplied = headers["x-mun-token"] ?? r.query["token"] ?? ""
        if supplied != token {
            respond(conn, status: 401, body: ["error": "unauthorized", "hint": "send X-Mun-Token header or ?token="])
            return
        }

        let bodyJSON = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]

        if path == "/" || path == "/api" {
            respond(conn, status: 200, body: [
                "name": "mun container remote api",
                "endpoints": [
                    "GET  /api/status",
                    "GET  /api/apps",
                    "POST /api/launch       {\"bundle\": \"XXX.app\"}",
                    "POST /api/install      {\"url\": \"https://.../app.ipa\"}",
                    "POST /api/clone        {\"bundle\": \"XXX.app\"}",
                    "GET  /api/mc?bundle=XXX.app",
                    "POST /api/mc           {\"bundle\": \"XXX.app\", \"profile\": {...}}",
                    "POST /api/mc/randomize {\"bundle\": \"XXX.app\", \"model\": \"iPhone17,1\"?}",
                    "POST /api/mc/remove    {\"bundle\": \"XXX.app\"}",
                ]
            ])
            return
        }

        switch (method, path) {
        case ("GET", "/api/status"):
            let infos = listAppInfos()
            respond(conn, status: 200, body: [
                "app": "mun container",
                "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?",
                "port": Int(runningPort),
                "apps": infos.count,
                "app_names": infos.map { $0.relativeBundlePath },
            ])
        case ("GET", "/api/debug-lang"):
            let key = UserDefaults.standard.string(forKey: "MCLanguageOverride")
            let viPath = Bundle.main.path(forResource: "vi", ofType: "lproj")
            let sample = "lc.settings.language".loc
            let sample2 = "lc.settings.dataManagement".loc
            respond(conn, status: 200, body: [
                "MCLanguageOverride": key ?? "(nil)",
                "default_is_vi_test": "lc.settings.language".loc,
                "vi_bundle_path": viPath ?? "(nil)",
                "sample_settings_language": sample,
                "sample_data_management": sample2,
            ])
        case ("GET", "/api/apps"):
            var list: [[String: Any]] = []
            for info in listAppInfos() {
                list.append([
                    "bundle_path": info.relativeBundlePath,
                    "name": info.displayName() ?? info.relativeBundlePath,
                    "bundle_id": info.bundleIdentifier() ?? "",
                    "hidden": info.isHidden,
                    "shared": info.isShared,
                    "containers": info.containers.map { $0.folderName },
                    "default_container": info.dataUUID ?? "",
                ])
            }
            respond(conn, status: 200, body: ["apps": list])
        case ("POST", "/api/launch"):
            guard let bundle = (bodyJSON["bundle"] as? String) ?? (r.query["bundle"]) else {
                respond(conn, status: 400, body: ["error": "missing 'bundle'"])
                return
            }
            var containerPart = ""
            if let container = bodyJSON["container"] as? String, !container.isEmpty {
                containerPart = "&container-folder-name=\(container)"
            }
            guard let url = URL(string: "livecontainer://livecontainer-launch?bundle-name=\(bundle)\(containerPart)") else {
                respond(conn, status: 400, body: ["error": "bad bundle name"])
                return
            }
            DispatchQueue.main.async {
                UIApplication.shared.open(url)
            }
            respond(conn, status: 200, body: ["ok": true, "launching": bundle])
        case ("POST", "/api/install"):
            guard let installUrl = (bodyJSON["url"] as? String) ?? (r.query["url"]), !installUrl.isEmpty else {
                respond(conn, status: 400, body: ["error": "missing 'url'"])
                return
            }
            guard let encoded = installUrl.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "livecontainer://install?url=\(encoded)") else {
                respond(conn, status: 400, body: ["error": "bad url"])
                return
            }
            DispatchQueue.main.async {
                UIApplication.shared.open(url)
            }
            respond(conn, status: 200, body: ["ok": true, "installing_from": installUrl])
        case ("POST", "/api/clone"):
            guard let bundle = (bodyJSON["bundle"] as? String) ?? r.query["bundle"], !bundle.isEmpty else {
                respond(conn, status: 400, body: ["error": "missing 'bundle'"])
                return
            }
            switch cloneApp(bundle: bundle) {
            case .success(let created):
                respond(conn, status: 200, body: created)
            case .failure(let err):
                respond(conn, status: 404, body: ["error": err, "bundle": bundle])
            }
        case ("GET", "/api/mc"):
            guard let bundle = r.query["bundle"] else {
                respond(conn, status: 400, body: ["error": "missing ?bundle="])
                return
            }
            if let profile = mcProfile(bundle: bundle) {
                respond(conn, status: 200, body: ["bundle": bundle, "profile": profile])
            } else {
                respond(conn, status: 404, body: ["error": "app not found", "bundle": bundle])
            }
        case ("POST", "/api/mc"):
            guard let bundle = bodyJSON["bundle"] as? String,
                  let profile = bodyJSON["profile"] as? [String: Any] else {
                respond(conn, status: 400, body: ["error": "need {bundle, profile}"])
                return
            }
            switch mcWrite(bundle: bundle, profile: profile, merge: true) {
            case .success(let merged):
                respond(conn, status: 200, body: ["ok": true, "profile": merged])
            case .failure(let err):
                respond(conn, status: 404, body: ["error": err])
            }
        case ("POST", "/api/mc/randomize"):
            guard let bundle = (bodyJSON["bundle"] as? String) ?? (r.query["bundle"]) else {
                respond(conn, status: 400, body: ["error": "missing 'bundle'"])
                return
            }
            let model = bodyJSON["model"] as? String
            let dict = NSMutableDictionary()
            if let model, !model.isEmpty {
                MCRandom.fillIdentity(forModel: model, into: dict)
            } else {
                MCRandom.fillIdentity(dict)
            }
            dict["enabled"] = true
            let profile = (dict as? [String: Any]) ?? [:]
            switch mcWrite(bundle: bundle, profile: profile, merge: false) {
            case .success(let written):
                respond(conn, status: 200, body: ["ok": true, "profile": written])
            case .failure(let err):
                respond(conn, status: 404, body: ["error": err])
            }
        case ("POST", "/api/mc/remove"):
            guard let bundle = (bodyJSON["bundle"] as? String) ?? (r.query["bundle"]) else {
                respond(conn, status: 400, body: ["error": "missing 'bundle'"])
                return
            }
            switch mcRemove(bundle: bundle) {
            case .success:
                respond(conn, status: 200, body: ["ok": true])
            case .failure(let err):
                respond(conn, status: 404, body: ["error": err])
            }
        default:
            respond(conn, status: 404, body: ["error": "not found", "path": path])
        }
    }

    // MARK: - MunChanger profile IO

    /// Enumerate installed apps directly from the Applications folders.
    /// Works in both UI and guest mode (DataManager.model is UI-only).
    private func listAppInfos() -> [LCAppInfo] {
        var out: [LCAppInfo] = []
        let fm = FileManager.default
        // In guest mode HOME is swapped to the guest container; LC_HOME_PATH
        // (set by LCBootstrap before the swap) points to the LC app home.
        let lcHome = ProcessInfo.processInfo.environment["LC_HOME_PATH"] ?? NSHomeDirectory()
        let localBase = URL(fileURLWithPath: lcHome).appendingPathComponent("Documents/Applications")
        for (base, isShared) in [(localBase, false), (LCPath.lcGroupBundlePath, true)] {
            guard let dirs = try? fm.contentsOfDirectory(atPath: base.path) else { continue }
            for dir in dirs where dir.hasSuffix(".app") {
                if let info = LCAppInfo(bundlePath: base.appendingPathComponent(dir).path) {
                    info.relativeBundlePath = dir
                    info.isShared = isShared
                    out.append(info)
                }
            }
        }
        return out
    }

    /// Copy an installed .app into a new folder. The copy gets a new display name and an empty data container.
    func cloneApp(bundle: String) -> Result<[String: Any], String> {
        guard let source = findAppInfo(bundle) else {
            return .failure("app not found: \(bundle)")
        }
        let fm = FileManager.default
        let base = applicationsBase(isShared: source.isShared)
        let sourceURL = base.appendingPathComponent(source.relativeBundlePath)
        guard fm.fileExists(atPath: sourceURL.path) else {
            return .failure("bundle folder missing: \(source.relativeBundlePath)")
        }

        let rawId = source.bundleIdentifier() ?? "App"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let safeId = String(rawId.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" })
        var folder = "\(safeId)_\(Int(Date().timeIntervalSince1970)).app"
        var dest = base.appendingPathComponent(folder)
        var guardN = 0
        while fm.fileExists(atPath: dest.path) && guardN < 5 {
            guardN += 1
            folder = "\(safeId)_\(Int(Date().timeIntervalSince1970))_\(guardN).app"
            dest = base.appendingPathComponent(folder)
        }

        do {
            try fm.copyItem(at: sourceURL, to: dest)
        } catch {
            return .failure("copy failed: \(error.localizedDescription)")
        }

        let siblings = listAppInfos().filter { $0.bundleIdentifier() == source.bundleIdentifier() }.count
        let baseName = (source.displayName() ?? rawId).replacingOccurrences(of: #" \d+$"#, with: "", options: .regularExpression)
        let newName = "\(baseName) \(siblings)"
        let plistURL = dest.appendingPathComponent("Info.plist")
        if let plist = NSMutableDictionary(contentsOf: plistURL) {
            plist["CFBundleDisplayName"] = newName
            if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0) {
                try? data.write(to: plistURL)
            }
        }

        guard let cloned = LCAppInfo(bundlePath: dest.path) else {
            try? fm.removeItem(at: dest)
            return .failure("cannot read cloned Info.plist")
        }
        cloned.relativeBundlePath = folder
        cloned.isShared = source.isShared
        cloned.autoSaveDisabled = true
        cloned.info()?.removeObject(forKey: "LCDataUUID")
        cloned.info()?.removeObject(forKey: "LCContainers")
        cloned.info()?.removeObject(forKey: "lastLaunched")
        cloned.installationDate = Date()
        cloned.autoSaveDisabled = false
        cloned.save()

        let created: [String: Any] = [
            "ok": true,
            "bundle_path": folder,
            "name": cloned.displayName() ?? newName,
            "bundle_id": cloned.bundleIdentifier() ?? rawId,
            "from": source.relativeBundlePath ?? "",
        ]
        attachCloneToUI(cloned)
        return .success(created)
    }

    private func applicationsBase(isShared: Bool) -> URL {
        if isShared { return LCPath.lcGroupBundlePath }
        let lcHome = ProcessInfo.processInfo.environment["LC_HOME_PATH"] ?? NSHomeDirectory()
        return URL(fileURLWithPath: lcHome).appendingPathComponent("Documents/Applications")
    }

    private func attachCloneToUI(_ info: LCAppInfo) {
        if let lcHome = ProcessInfo.processInfo.environment["LC_HOME_PATH"], lcHome != NSHomeDirectory() {
            return
        }
        DispatchQueue.main.async {
            let model = DataManager.shared.model
            let folder = info.relativeBundlePath ?? ""
            if info.isHidden {
                if model.hiddenApps.contains(where: { $0.appInfo.relativeBundlePath == folder }) { return }
                model.hiddenApps.append(LCAppModel(appInfo: info))
            } else {
                if model.apps.contains(where: { $0.appInfo.relativeBundlePath == folder }) { return }
                model.apps.append(LCAppModel(appInfo: info))
            }
        }
    }

    private func findAppInfo(_ bundle: String) -> LCAppInfo? {
        let base = bundle.lowercased().hasSuffix(".app") ? String(bundle.dropLast(4)).lowercased() : bundle.lowercased()
        for info in listAppInfos() {
            let folder = info.relativeBundlePath.lowercased().hasSuffix(".app") ? String(info.relativeBundlePath.dropLast(4)).lowercased() : info.relativeBundlePath.lowercased()
            if folder == base
                || info.relativeBundlePath == bundle
                || (info.displayName()?.lowercased() == base)
                || (info.bundleIdentifier()?.lowercased() == base)
                || (base.count >= 4 && (folder.hasSuffix(".\(base)") || folder.contains(base))) {
                return info
            }
        }
        return nil
    }

    /// Mirror of LCAppModel.runApp's container bootstrap, operating on LCAppInfo
    /// so it also works before first launch and in guest mode.
    private func ensureContainerURL(_ info: LCAppInfo) -> URL? {
        if let existing = info.containers.first(where: { $0.folderName == info.dataUUID })
            ?? info.containers.first {
            return existing.containerURL
        }
        let newName = UUID().uuidString
        let c = LCContainer(folderName: newName, name: newName, isShared: info.isShared)
        info.containers = (info.containers + [c])
        c.makeLCContainerInfoPlist(appIdentifier: info.bundleIdentifier() ?? "", keychainGroupId: Int.random(in: 0..<SharedModel.keychainAccessGroupCount))
        info.dataUUID = newName
        return c.containerURL
    }

    private func mcPlistURL(for bundle: String) -> URL? {
        guard let info = findAppInfo(bundle) else { return nil }
        guard let containerURL = ensureContainerURL(info) else { return nil }
        return containerURL.appendingPathComponent("Library/Preferences/com.mun.changer.plist")
    }

    private func mcProfile(bundle: String) -> [String: Any]? {
        guard let url = mcPlistURL(for: bundle) else { return nil }
        if let dict = NSDictionary(contentsOf: url) as? [String: Any] {
            return dict
        }
        // app exists but no profile yet → empty profile
        return [:]
    }

    private func mcWrite(bundle: String, profile: [String: Any], merge: Bool) -> Result<[String: Any], String> {
        guard let url = mcPlistURL(for: bundle) else {
            return .failure("app not found or no data container: \(bundle)")
        }
        var out = profile
        if merge, let existing = NSDictionary(contentsOf: url) as? [String: Any] {
            out.merge(existing) { current, _ in current }
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try (out as NSDictionary).write(to: url)
            return .success(out)
        } catch {
            return .failure("write failed: \(error.localizedDescription)")
        }
    }

    private func mcRemove(bundle: String) -> Result<Void, String> {
        guard let url = mcPlistURL(for: bundle) else {
            return .failure("app not found or no data container: \(bundle)")
        }
        try? FileManager.default.removeItem(at: url)
        return .success(())
    }
}
