#!/usr/bin/env python3
# AppDelegate.swift に PencilKitPlugin の登録コードを注入する。
# storyboard を書き換えずにプラグインを登録するための方法。
# 起動完了後、rootViewController(CAPBridgeViewController) の bridge に
# registerPluginInstance で登録する。bridge 準備のため少し遅延させる。
import sys

path = sys.argv[1]
src = open(path).read()

if "PencilKitPlugin" in src:
    print("既に注入済み")
    sys.exit(0)

# capacitorDidLoad を使う方式に切り替えるのが最も確実。
# AppDelegate の didFinishLaunchingWithOptions の return true 直前に、
# メインスレッドで rootViewController を取得して登録するコードを差し込む。
inject = '''
        // --- PencilKitPlugin 登録（自動注入） ---
        DispatchQueue.main.async {
            func registerPK() {
                if let vc = application.windows.first?.rootViewController as? CAPBridgeViewController {
                    vc.bridge?.registerPluginInstance(PencilKitPlugin())
                } else if let vc = (UIApplication.shared.connectedScenes
                            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
                            .first?.rootViewController) as? CAPBridgeViewController {
                    vc.bridge?.registerPluginInstance(PencilKitPlugin())
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { registerPK() }
                }
            }
            registerPK()
        }
        // --- ここまで ---
'''

# Capacitor を import しているか確認し、なければ追加
if "import Capacitor" not in src:
    src = src.replace("import UIKit", "import UIKit\nimport Capacitor", 1)

# return true を探して、その前に inject を入れる
marker = "return true"
idx = src.find(marker)
if idx == -1:
    print("return true が見つからない。手動確認が必要。", file=sys.stderr)
    sys.exit(1)

src = src[:idx] + inject + "\n        " + src[idx:]
open(path, "w").write(src)
print("AppDelegate に登録コードを注入しました")
