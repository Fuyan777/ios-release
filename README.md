# ios-release

iOSアプリを **App Store に申請できる状態** まで、Claude に進めてもらうためのスキル集です。
初めてアプリを出す人でも、Claude に話しかけるだけで進められるように作っています。

あなたがやるのは、Claude に頼まれたときの「確認・承認」と、Apple のサイトでしかできない作業（アプリの登録・APIキーの発行・審査への提出）だけです。その手順も Claude が1つずつ案内します。

```
① 企画（Claude）           何を作るかをまとめる
🧑 企画の承認
② 開発（Claude）           作って、シミュレータで動かす
🧑 できたアプリの確認
③ リリース準備（Claude）   fastlane・説明文・スクショを用意して App Store Connect に上げる
🧑 Apple のサイトで残りを入力して「審査へ提出」
```

すでにアプリができている人は、③から始められます。

## 用意するもの

- Mac と [Xcode](https://apps.apple.com/jp/app/xcode/id497799835)
- [Claude Code](https://claude.com/claude-code)（ターミナル版・デスクトップアプリのどちらでも）
- [Apple Developer Program](https://developer.apple.com/jp/programs/) への登録（年会費が必要。途中で Claude が案内します）

## 使い方

### 1. スキルを入れる

いちばん簡単なのは、Claude Code に次の文をそのまま貼ることです。

```text
https://github.com/Fuyan777/ios-release を git clone して、skills フォルダの中身を ~/.claude/skills/ にコピーして
```

自分で入れるなら、ターミナルで次を実行します。

```bash
git clone https://github.com/Fuyan777/ios-release.git /tmp/ios-release && mkdir -p ~/.claude/skills && cp -R /tmp/ios-release/skills/* ~/.claude/skills/
```

<details>
<summary>プラグインとして入れる（Claude Code のターミナル版）</summary>

```text
/plugin marketplace add Fuyan777/ios-release
/plugin install ios-release@ios-release
```

</details>

入れたら Claude Code を開き直します。

### 2. アプリのフォルダで Claude に頼む

アプリのフォルダ（まだない人は、作りたい場所の空のフォルダ）で Claude Code を開き、次のように話しかけます。

**これからアプリを作る人**

```text
auto-release スキルを使って、〇〇のアプリを作って App Store に申請できる状態まで進めて
```

**もうアプリがある人**

```text
appstore-first-upload スキルを使って、このアプリを App Store に申請できる状態にして
```

あとは Claude の案内に沿って進めます。途中で止まっても「続きを進めて」と言えば、`RELEASE.md` に書かれた進み具合から再開します。

## 入っているスキル

| スキル | やること |
| --- | --- |
| [auto-release](skills/auto-release/SKILL.md) | 企画 → 開発 → リリース準備を順に進め、人の出番で止まる。会話で進めるか、GitHub の issue で進めるかを選べる |
| [appstore-first-upload](skills/appstore-first-upload/SKILL.md) | fastlane の設定、説明文・スクショの用意、App Store Connect へのアップロード。Apple のサイトでの作業は1つずつ案内する |

## Claude がしないこと

- **審査への提出はしません。** 最後の「審査へ提出」ボタンはあなたが押します
- APIキー（`.p8` ファイル）の中身は読みません。キーはリポジトリの外に置き、git にも入れません
- 課金・値段・ストアの設定は変えません

## GitHub の issue で進める（慣れた人向け）

`auto-release` は、人の出番を GitHub issue にして止まることもできます。issue を閉じると承認になり、Claude が続きを進めます。定期実行と組み合わせると、アイデアを issue に書いておくだけで企画から進めてもらえます。

- `gh`（GitHub CLI）と `jq` が必要です
- 初回に `skills/auto-release/scripts/issue.sh setup` でラベルを作ります
- GitHub Projects にも載せたいときは、環境変数 `PROJECT_NUMBER` を設定します

詳しくは [auto-release の SKILL.md](skills/auto-release/SKILL.md) を見てください。

## ライセンス

MIT
