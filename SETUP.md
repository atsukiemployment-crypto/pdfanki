# iPadだけで TestFlight まで進める手順（フォルダ不要・フラット版）

GitHubのWebアップロードはフォルダを扱えないため、**全ファイルをリポジトリ直下にそのまま置く**構成にしてあります。アップロードするのは「ファイルだけ」。フォルダ操作は一切ありません。ビルド時にCodemagicが自動でフォルダ構成へ組み直します。

## アップロードするファイル（このフォルダの中身ぜんぶ・13個）

```
index.html               ← Webアプリ本体
manifest.webmanifest
icon-180.png             ← PWAアイコン
icon-192.png
icon-512.png
PencilKitPlugin.swift     ← ネイティブ描画プラグイン
PencilKitPlugin.m
add_plugin_files.rb       ← CI補助スクリプト
icon-only.png             ← アプリアイコン素材（@capacitor/assets用）
splash.png                ← 起動画面素材
splash-dark.png
capacitor.config.json     ← アプリID・名前
package.json
codemagic.yaml            ← クラウドビルド設定
```

※ 14ファイルあります（上の一覧13個 + codemagic.yaml）。全部「ただのファイル」なので、Upload filesでまとめて選んで上げられます。

## 手順（すべてiPadのブラウザで完結）

### 1. GitHubにファイルを上げる
1. GitHub（github.com）でアカウント作成 → 右上「+」→「New repository」でリポジトリを作成（名前は何でもOK。Privateで構いません）
2. 作成後の画面で「uploading an existing file」リンク、または「Add file > Upload files」をタップ
3. **このフォルダの中の全ファイルを選択**してアップロード（iPadなら「写真/ファイルを選択」から複数選択。一度に選べなければ数回に分けてOK）
4. 下の「Commit changes」をタップ
5. リポジトリのトップに `codemagic.yaml` や `index.html` が**直接見えていれば成功**（`appstore`のようなフォルダが挟まっていないこと）

### 2. Apple Developer Program に登録
- developer.apple.com で登録（年99ドル）。TestFlightにも販売にも必須。

### 3. App Store Connect の準備（appstoreconnect.apple.com）
- 「ユーザとアクセス > 統合 > App Store Connect API」でAPIキーを発行（Admin権限）。**`.p8`ファイル・Key ID・Issuer ID**を控える
- 「マイApp > +」で新規App作成。Bundle IDは下の手順5で決めるものと一致させる

### 4. Codemagic に登録してGitHubと接続
- codemagic.io に無料登録 → 先ほどのGitHubリポジトリを接続
- Team settings > Integrations > App Store Connect に、手順3のAPIキーを **ASC_API_KEY** という名前で登録

### 5. Bundle ID を自分のものに書き換え（2か所）
GitHubのファイル一覧から各ファイルをタップ → 右上の鉛筆アイコンで編集できます。
- `capacitor.config.json` の `com.YOURNAME.pdfstudy`
- `codemagic.yaml` の `com.YOURNAME.pdfstudy`

`YOURNAME` を自分の名前やID（英数字）に変えるだけ。例: `com.taro.pdfstudy`。**2か所を完全に同じ文字列**にすること。

### 6. ビルド実行
- Codemagicでワークフロー「ios-testflight」を実行（署名証明書はCodemagicが自動生成）
- 成功すると自動でTestFlightにアップロードされる

### 7. iPadで試す
- iPadに「TestFlight」アプリを入れ、自分のApple IDでサインイン → アプリが現れたらインストール

### 8. 販売（任意）
- App Store Connectで価格・スクリーンショット・説明文・**プライバシーポリシーURL（必須）**を用意して審査提出

## Bundle ID 早見表（手順3・5・App Store Connectで全部一致させる）

| 場所 | 何を書くか |
|---|---|
| capacitor.config.json の appId | com.あなたのID.pdfstudy |
| codemagic.yaml の bundle_identifier | 上と同じ |
| App Store Connect の新規App | 上と同じ |

この3つがズレると署名・アップロードで必ず失敗します。コピペで揃えるのが安全です。

## 注意
- **Swift部分は初回ビルドが答え合わせ**です。エラーが出たらCodemagicのログをそのまま貼ってください。修正版を出します（1〜2往復見込み）。
- アプリ名「PDF Study」はそのまま使えますが、似た名前の既存アプリがないか App Store で一度検索しておくと安心です。

## 費用
- GitHub / Codemagic: 無料枠でOK
- Apple Developer Program: 年99ドル
