#!/usr/bin/env bash
# 親issue（AIが進める案件）と、人間がやるステップのissueを作って Project に載せる。
#
#   issue.sh setup                                                ラベルを作る（初回だけ）
#   issue.sh start  <タイトル> <本文ファイル>                     親issueを作る → 番号を出力
#   issue.sh step   <親番号> <plan|review|release> <タイトル> <本文ファイル>
#                                                                人間のステップissueを作る → 番号を出力
#   issue.sh status <親番号>                                      サブissueの状態を一覧する
#   issue.sh queue                                                今進められる案件と次の作業を一覧する
#   issue.sh ideas                                                まだ着手していない idea の issue を一覧する
#   issue.sh claim  <番号>                                        idea の issue を親issueにして着手する
#
# issue の操作は REST API だけを使う（claude on the web では GraphQL が使えないため）。
# GitHub Projects への追加は PROJECT_NUMBER があり GraphQL が使えるときだけ行い、それ以外は飛ばす。
# 環境変数で差し替えられる：REPO（owner/name）、PROJECT_OWNER（既定はリポジトリのオーナー）、PROJECT_NUMBER（既定なし）
set -euo pipefail

REPO=${REPO:-$(git remote get-url origin | sed -E 's#\.git$##; s#.*[:/]([^/]+/[^/]+)$#\1#')}
OWNER=${PROJECT_OWNER:-${REPO%%/*}}
NUMBER=${PROJECT_NUMBER:-}
ME=$(gh api user -q .login 2>/dev/null || true)

# Project に追加し、Status / Priority / Size を名前で設定する
add_to_project() {
  local url=$1 status=$2 priority=${3:-} size=${4:-}
  local project_id item_id fields
  [ -z "$NUMBER" ] && return 0
  if ! project_id=$(gh project view "$NUMBER" --owner "$OWNER" --format json -q .id 2>/dev/null); then
    echo "Project に追加できなかったので飛ばしました（GraphQL が使えない環境）" >&2
    return 0
  fi
  item_id=$(gh project item-add "$NUMBER" --owner "$OWNER" --url "$url" --format json -q .id)
  fields=$(gh project field-list "$NUMBER" --owner "$OWNER" --format json)
  set_option() {
    local field=$1 option=$2 field_id option_id
    [ -z "$option" ] && return
    field_id=$(jq -r --arg f "$field" '.fields[] | select(.name==$f) | .id' <<<"$fields")
    option_id=$(jq -r --arg f "$field" --arg o "$option" '.fields[] | select(.name==$f) | .options[] | select(.name==$o) | .id' <<<"$fields")
    gh project item-edit --id "$item_id" --project-id "$project_id" --field-id "$field_id" --single-select-option-id "$option_id" >/dev/null
  }
  set_option Status "$status"
  set_option Priority "$priority"
  set_option Size "$size"
}

# issue を作り、番号と URL をタブ区切りで出す。3つ目以降の引数はラベル
create_issue() {
  local title=$1 body=$2; shift 2
  local labels
  labels=$(printf '%s\n' "$@" | jq -R . | jq -s .)
  jq -n --arg t "$title" --rawfile b "$body" --argjson l "$labels" --arg a "$ME" \
      '{title: $t, body: $b, labels: $l, assignees: (if $a == "" then [] else [$a] end)}' |
    gh api "repos/$REPO/issues" -X POST --input - -q '"\(.number)\t\(.html_url)"'
}

# リポジトリに書き込める人（オーナー・メンバー・コラボレーター）か。公開リポジトリでは誰でも issue やコメントを書けるので、
# それ以外の人が書いたものは AI への指示として扱わない
TRUSTED='.author_association == "OWNER" or .author_association == "MEMBER" or .author_association == "COLLABORATOR"'

# 着手していない idea を古い順に「番号<TAB>タイトル」で出す（信頼できる人が起票したものだけ）
list_ideas() {
  gh api "repos/$REPO/issues?labels=idea&state=open&sort=created&direction=asc&per_page=100" \
    -q ".[] | select(.pull_request | not) | select($TRUSTED) | select(all(.labels[]; .name != \"ai-working\")) | \"\\(.number)\\t\\(.title)\""
}

case ${1:-} in
  setup)
    while IFS=$'\t' read -r name color desc; do
      gh api "repos/$REPO/labels" -X POST -f name="$name" -f color="$color" -f description="$desc" >/dev/null 2>&1 \
        && echo "作成: $name" || echo "あり: $name"
    done <<'LABELS'
idea	fbca04	アイデア。AIが拾って企画から始める
ai-working	1d76db	AIが進めている案件
human	d93f0b	人がやるタスク
step:plan	c5def5	企画の承認
step:review	c5def5	できたアプリの確認
step:release	c5def5	Apple のサイトでの作業と審査への提出
approved	0e8a16	承認（閉じる代わりに付けてもよい）
LABELS
    ;;
  start)
    IFS=$'\t' read -r num url < <(create_issue "$2" "$3" ai-working)
    add_to_project "$url" "In progress"
    echo "$num"
    ;;
  step)
    parent=$2 step=$3
    case $step in
      plan|review) size=S ;;
      release) size=XS ;;
      *) echo "step は plan / review / release のどれか" >&2; exit 1 ;;
    esac
    IFS=$'\t' read -r num url < <(create_issue "$4" "$5" human "step:$step")
    id=$(gh api "repos/$REPO/issues/$num" -q .id)
    gh api "repos/$REPO/issues/$parent/sub_issues" -X POST -F sub_issue_id="$id" >/dev/null
    add_to_project "$url" Ready P1 "$size"
    echo "$num"
    ;;
  status)
    gh api "repos/$REPO/issues/$2/sub_issues" \
      -q '.[] | "#\(.number)\t\(.state)\t\([.labels[].name] | join(","))\t\(.title)"'
    ;;
  queue)
    # 進められる案件と次の作業を出す。人間の返事待ち（wait）は出さない
    #   plan / dev / release：そのステップの作業、fix：差し戻しの対応、close：親issueを閉じる
    parents=$(gh api "repos/$REPO/issues?labels=ai-working&state=open&per_page=100" -q '.[] | select(.pull_request | not) | .number')
    for parent in $parents; do
      subs=$(gh api "repos/$REPO/issues/$parent/sub_issues")
      last=$(jq -r 'map(select(any(.labels[]; .name | startswith("step:")))) | last // empty' <<<"$subs")
      if [ -z "$last" ]; then echo -e "#$parent\tplan"; continue; fi
      step=$(jq -r '.labels[].name | select(startswith("step:")) | sub("step:"; "")' <<<"$last")
      num=$(jq -r .number <<<"$last")
      done_=$(jq -r '.state == "closed" or any(.labels[]; .name == "approved")' <<<"$last")
      if [ "$done_" = true ]; then
        case $step in plan) echo -e "#$parent\tdev" ;; review) echo -e "#$parent\trelease" ;; release) echo -e "#$parent\tclose" ;; esac
      else
        # AIのコメントは「🤖」で始める。信頼できる人の最後のコメントが人間のものなら差し戻し
        latest=$(gh api "repos/$REPO/issues/$num/comments?per_page=100" -q "map(select($TRUSTED)) | last.body // \"\"")
        [ -n "$latest" ] && [[ $latest != 🤖* ]] && echo -e "#$parent\tfix #$num"
      fi
    done
    list_ideas | awk -F'\t' '{ print "#" $1 "\tidea" }'
    ;;
  ideas)
    list_ideas | sed 's/^/#/'
    ;;
  claim)
    gh api "repos/$REPO/issues/$2/labels" -X POST -f "labels[]=ai-working" >/dev/null
    add_to_project "$(gh api "repos/$REPO/issues/$2" -q .html_url)" "In progress"
    echo "$2"
    ;;
  *)
    sed -n '2,15p' "$0"; exit 1 ;;
esac
