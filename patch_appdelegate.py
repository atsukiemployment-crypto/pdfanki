#!/usr/bin/env python3
# AppDelegate.swift に PencilKitPlugin の登録コードを注入する。
# storyboard を書き換えずにプラグインを登録するための方法。
#
# 【初回起動でボタンが効かない問題への対策】
# 起動完了直後は rootViewController(CAPBridgeViewController) がまだ
# 用意されていないことがある。1回だけのリトライでは間に合わず登録が
# 漏れることがあったため、用意できるまで短い間隔で最大50回（約5秒）
# リトライし、確実に登録されるようにする。
import sys

path = sys.argv[1]
src = open(path).read()

if "PencilKitPlugin" in src:
    print("既に注入済み")
    sys.exit(0)

inject = '''
        // --- PencilKitPlugin 登録（自動注入・初回起動対策版） ---
        func findBridgeVC() -> CAPBridgeViewController? {
            for scene in UIApplication.shared.connectedScenes {
                if let ws = scene as? UIWindowScene {
                    for w in ws.windows {
                        if let vc = w.rootViewController as? CAPBridgeViewController {
                            return vc
                        }
                    }
                }
            }
            if let vc = self.window?.rootViewController as? CAPBridgeViewController {
                return vc
            }
            return nil
        }
        var pkRegisterAttempts = 0
        func registerPK() {
            if let vc = findBridgeVC(), let b = vc.bridge {
                b.registerPluginInstance(PencilKitPlugin())
                return
            }
            pkRegisterAttempts += 1
            if pkRegisterAttempts < 50 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { registerPK() }
            }
        }
        DispatchQueue.main.async { registerPK() }
        // --- ここまで ---
'''

if "import Capacitor" not in src:
    src = src.replace("import UIKit", "import UIKit\nimport Capacitor", 1)

marker = "return true"
idx = src.find(marker)
if idx == -1:
    print("return true が見つからない。手動確認が必要。", file=sys.stderr)
    sys.exit(1)

src = src[:idx] + inject + "\n        " + src[idx:]
open(path, "w").write(src)
print("AppDelegate に登録コードを注入しました（初回起動対策版）")
