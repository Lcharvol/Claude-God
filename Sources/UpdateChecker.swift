// UpdateChecker.swift
// Checks GitHub releases for updates and provides install functionality

import Foundation
import AppKit

class UpdateChecker: ObservableObject {

    @Published var updateAvailable = false
    @Published var latestVersion = ""
    @Published var downloadURL: URL?

    static let currentVersion: String = Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
    ) as? String ?? "1.0.0"

    func check() {
        guard let url = URL(string: "https://api.github.com/repos/Lcharvol/Claude-God/releases/latest") else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            guard let data = data, error == nil else { return }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let assets = json["assets"] as? [[String: Any]] else { return }

            let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            DispatchQueue.main.async {
                guard Self.isNewer(remote: remoteVersion, current: Self.currentVersion) else { return }

                self?.latestVersion = remoteVersion
                self?.updateAvailable = true

                if let dmgAsset = assets.first(where: { ($0["name"] as? String)?.hasSuffix(".dmg") == true }),
                   let urlString = dmgAsset["browser_download_url"] as? String {
                    self?.downloadURL = URL(string: urlString)
                }
            }
        }.resume()
    }

    func install() {
        guard let url = downloadURL else { return }
        NSWorkspace.shared.open(url)
    }

    static func isNewer(remote: String, current: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let c = current.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, c.count) {
            let rv = i < r.count ? r[i] : 0
            let cv = i < c.count ? c[i] : 0
            if rv > cv { return true }
            if rv < cv { return false }
        }
        return false
    }
}
