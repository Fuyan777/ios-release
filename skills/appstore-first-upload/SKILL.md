---
name: appstore-first-upload
description: >
  iOSアプリを初めて App Store に出す人向けに、fastlane の設定、ストアの説明文とスクショの用意、
  App Store Connect へのアップロードまでを Claude が進める。人がやるのは Apple のサイトでしかできないこと
  （アプリの登録・APIキーの発行・プライバシーなどの回答・審査への提出）だけにし、その手順は1つずつ案内する。
  「初めてリリースしたい」「App Store に出したい」「ストアの説明文とスクショを上げて」「fastlane を設定して」
  「App Store Connect にアップロードして」と言われたときに使う。
---

# 初めての App Store アップロード

相手は初めてアプリを出す人。専門用語には一言の説明をつけ、人に頼む作業は**1回に1つ**、クリックする場所を順番に書いて頼む。

```
① 今の状態を確かめる        Claude
② Apple のサイトでの準備     人（アプリの登録・APIキー）
③ fastlane を入れて設定する   Claude
④ 説明文を書く              Claude が書き、人が確かめる
⑤ スクショを撮る            Claude
⑥ 確かめて、アップロードする   Claude
⑦ 残りを Apple のサイトで     人（プライバシー・年齢・値段・審査への提出）
```

## 守ること

- **APIキー（`.p8`）の中身を読まない・表示しない・コミットしない。** キーはリポジトリの外（`~/.appstoreconnect/private_keys/`）に置いてもらい、Claude はファイルの場所だけを使う
- **審査には出さない。** アップロードまでが Claude の仕事。提出は人が App Store Connect の画面でする
- 審査用の連絡先（`fastlane/metadata/review_information/`。電話番号・デモアカウント）は個人情報。中身は人に書いてもらい、git に入れない
- すでに `Fastfile` があるとき（①で見つかったとき。上のフォルダにある共通のものも含む）は新しく作らない。③は飛ばし、その lane と置き場所（`metadata_path` など）に合わせて④⑤⑥をやる

## ① 今の状態を確かめる

次を調べて、人に「できていること・これからやること」を短く伝える。

```bash
ls *.xcodeproj *.xcworkspace 2>/dev/null          # プロジェクト
xcodebuild -list -project <名前>.xcodeproj         # スキーム
xcodebuild -showBuildSettings -project <名前>.xcodeproj -scheme <スキーム> -configuration Release \
  | grep -E ' (PRODUCT_BUNDLE_IDENTIFIER|MARKETING_VERSION|DEVELOPMENT_TEAM|TARGETED_DEVICE_FAMILY|CODE_SIGN_STYLE) = '
which fastlane; fastlane --version | tail -1
# Fastfile（このフォルダから git のルートまでさかのぼって探す。複数アプリで共通の Fastfile がルートにあることもある）
d=$PWD; while :; do [ -f "$d/fastlane/Fastfile" ] && echo "$d/fastlane/Fastfile"; [ -e "$d/.git" ] || [ "$d" = / ] && break; d=$(dirname "$d"); done
echo "${ASC_KEY_ID:+キーID あり} ${ASC_ISSUER_ID:+発行者ID あり} ${ASC_PRIVATE_KEY_PATH:+キーの場所 あり}"
```

- `xcodebuild` が動かなければ、Mac の App Store から Xcode を入れて一度開いてもらう（`xcode-select -p` が `/Applications/Xcode.app/...` を指していなければ `sudo xcode-select -s /Applications/Xcode.app` を人に実行してもらう）
- `brew` がなければ、fastlane を入れる前に [Homebrew](https://brew.sh) を入れてもらう（ページのコマンドをターミナルに貼るだけ）
- アプリのアイコン（`Assets.xcassets/AppIcon.appiconset` の 1024×1024 の PNG）がなければアップロードで止まる。人に用意してもらう
- `DEVELOPMENT_TEAM` が空なら、②の前に Xcode で「Signing & Capabilities → Team」を選んでもらう
- `TARGETED_DEVICE_FAMILY` に `2`（iPad）が入っていたら、iPad のスクショも要る。初めてなら「iPhone だけにする」こともできると伝えて、どちらにするか聞く

## ② Apple のサイトでの準備（人）

できていないものだけを、1つずつ頼む。終わったと言われるまで待つ。

1. **Apple Developer Program**（年会費あり）に入っている。入っていなければ developer.apple.com から登録してもらう
2. **App Store Connect にアプリを登録する**（APIでは作れないので人の作業）
   - appstoreconnect.apple.com →「アプリ」→ 左上の「＋」→「新規アプリ」
   - プラットフォーム: iOS／名前: ストアに出す名前（あとで変えられる。ほかのアプリと同じ名前は使えない）／プライマリ言語: 日本語／バンドルID: ①で調べたもの／SKU: 何でもよい（例: アプリ名）
3. **APIキーを作る**（fastlane が App Store Connect に入るための鍵）
   - App Store Connect →「ユーザとアクセス」→「統合」→「App Store Connect API」→「チームキー」の「＋」
   - 名前: 何でもよい（例: fastlane）／アクセス: **App Manager**
   - 「キーID」と、ページ上部の「発行者ID（Issuer ID）」を控える。「APIキーをダウンロード」で `.p8` を保存する（**1回しかダウンロードできない**）
   - `.p8` は `~/.appstoreconnect/private_keys/` に移してもらう
4. **環境変数を設定する**: 人に `~/.zshrc` へ次を足してもらい、ターミナルを開き直してもらう（値は人が入れる）

   ```bash
   export ASC_KEY_ID="キーID"
   export ASC_ISSUER_ID="発行者ID"
   export ASC_PRIVATE_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_キーID.p8"
   export LANG=en_US.UTF-8   # fastlane が日本語を正しく扱うため
   ```

## ③ fastlane を入れて設定する（Claude）

- fastlane がなければ `brew install fastlane`（入れる前に人に一言ことわる）
- プロジェクトのフォルダ（`.xcodeproj` がある場所）に `fastlane/` を作り、[templates/Fastfile](templates/Fastfile) と [templates/Appfile](templates/Appfile) をコピーして `__SCHEME__`・`__PROJECT__`（例: `MyApp.xcodeproj`）・`__BUNDLE_ID__` を埋める
- `.gitignore` に足す（なければ作る）

  ```
  *.p8
  fastlane/report.xml
  fastlane/build/
  fastlane/metadata/review_information/
  ```

- 暗号化を使っていない普通のアプリなら、ビルドの設定に `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` を足す（アップロードのたびに出る「輸出コンプライアンス」の質問が省ける）。HTTPS で通信するだけなら NO でよい。独自の暗号を使っているなら人に聞く

## ④ 説明文を書く（Claude が書き、人が確かめる）

コード・README・画面を読んで、アプリが何をするかをつかんでから書く。**できないことは書かない**（審査で落ちる）。

`fastlane/metadata/` に置く（言語のフォルダは日本語なら `ja`。②で選んだプライマリ言語と合わせる）。

| ファイル | 中身 | 上限 | 必須 |
| --- | --- | --- | --- |
| `ja/name.txt` | アプリ名（②で登録した名前） | 30文字 | ○ |
| `ja/subtitle.txt` | 名前の下に出るひとこと | 30文字 | |
| `ja/description.txt` | 説明。最初の3行で何ができるかが分かるように | 4000文字 | ○ |
| `ja/keywords.txt` | 検索されたい言葉をカンマ区切り（スペースなし）。名前に入っている言葉は入れなくてよい | 100文字 | ○ |
| `ja/promotional_text.txt` | 説明の上に出る宣伝文（審査なしで変えられる） | 170文字 | |
| `ja/support_url.txt` | 問い合わせ先のページのURL | | ○ |
| `ja/privacy_url.txt` | プライバシーポリシーのURL | | ○ |
| `ja/release_notes.txt` | 新しいバージョンの内容（初回は空でよい） | 4000文字 | |
| `copyright.txt` | 例: `2026 山田太郎` | | ○ |
| `primary_category.txt` | カテゴリ。例: `PHOTO_AND_VIDEO` `UTILITIES` `LIFESTYLE` `PRODUCTIVITY` `ENTERTAINMENT` `GAMES` | | ○ |

- サポートとプライバシーポリシーのページがなければ、文面を Claude が書き、公開の仕方（GitHub Pages・Notion の公開ページなど）を提案する。公開は人がする
- 書いたら、名前・サブタイトル・説明の最初の3行・キーワードを人に見せて確かめてもらう

## ⑤ スクショを撮る（Claude）

App Store は **iPhone 6.9インチ**（1320×2868 など）のスクショが要る。シミュレータで撮る。

```bash
xcrun simctl list devices available | grep "Pro Max"     # いちばん新しい Pro Max を使う
xcrun simctl boot "<Pro Max の名前>"
xcrun simctl status_bar booted override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
# アプリを入れて開き、見せたい画面にしてから
xcrun simctl io booted screenshot fastlane/screenshots/ja/01_<画面>.png
```

- 3〜5枚（最大10枚）。**ファイル名の順にストアに並ぶ**ので、いちばん見せたい画面を `01_` にする
- 空っぽの画面は撮らない。見本のデータを入れて、使っている様子が分かる画面にする。人の顔・本名・個人の写真は写さない
- iPad も出すなら、iPad Pro 13インチのシミュレータで同じように撮る（2064×2752 など）
- 撮ったら人に見せて、並びと選び方を確かめてもらう

## ⑥ 確かめて、アップロードする（Claude）

```bash
bash <このスキルのフォルダ>/scripts/check.sh fastlane     # 文字数・スクショの大きさ・秘密のファイル
fastlane upload_metadata                                  # 説明文とスクショ
fastlane upload_build                                     # ビルド（数分〜十数分かかる）
```

- check.sh が NG を出したら直してから上げる
- よくあるエラー

| エラー | 原因と直し方 |
| --- | --- |
| `Could not find app with bundle identifier` | ②のアプリ登録がまだ、またはバンドルIDが違う |
| `401` / `NOT_AUTHORIZED` | 環境変数がない・キーIDや発行者IDの写し間違い・アクセスが App Manager でない |
| `invalid screenshot size` | ⑤の大きさが違う。check.sh で確かめて撮り直す |
| `No signing certificate` / `No Account for Team` | Xcode で Team が選ばれていない（①） |
| `The bundle version must be higher` | 同じビルド番号が上がっている。もう一度 `upload_build` すれば次の番号になる |

- ビルドは上げてから10〜30分ほど「処理中」になる。終わると App Store Connect のバージョンのページで選べるようになる

## ⑦ 残りを Apple のサイトで（人）

最後に、次のチェックリストを人に渡す。**Claude が答えを用意できるものは、答えの案も書いておく**（コードを読んで、集めているデータ・通信・課金を調べる）。

1. **App のプライバシー**（「アプリ」→ 左の「App のプライバシー」）: 集めるデータの有無。端末の中だけで動き、データを送らないなら「データを収集しない」
2. **年齢制限**（アプリ情報 →「年齢制限」）: 質問に答える。暴力・ギャンブルなどがなければ、ほぼ「なし」
3. **価格と配信状況**: 無料か有料か、配信する国
4. **アプリ内課金**があるなら、商品を登録して、このバージョンに追加する
5. **バージョンのページ**:「ビルド」で⑥で上げたビルドを選ぶ。審査用の連絡先（名前・電話番号・メール）を入れる。ログインが要るアプリならデモアカウントも
6. 右上の「審査用に追加」→「審査へ提出」

審査は1〜3日ほど。結果はメールで届く。リジェクト（差し戻し）されたら、理由の文面を見せてもらえば直し方を一緒に考える。

## 2回目からのリリース

- 説明文やスクショを変えたら `fastlane upload_metadata`、新しいビルドは `fastlane upload_build`
- バージョンを上げるとき（1.0 → 1.1）は、Xcode の Version（`MARKETING_VERSION`）を上げ、App Store Connect で新しいバージョンを作ってから上げる。`ja/release_notes.txt` に変更点を書く
