#!/bin/bash
set -e

if [ $# -eq 0 ]; then
  echo "Usage: ai-next.sh [-to <ai_command>] [-model <model_name>] [-with-logs] <-research|-design|-implement|-review|-test|-publish-obsidian> \"Task description\" [\"Parallel Task 2\" ...]"
  exit 1
fi

CMD_ARRAY=("agy")
ORIGINAL_AI="agy"
MODEL_NAME=""
WITH_LOGS=0

if [ -f ".obsidian_project_name" ]; then
  REPO_DIR=$(cat .obsidian_project_name)
else
  REPO_DIR=$(basename "$PWD")
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    -to) ORIGINAL_AI="$2"; CMD_ARRAY=("$2"); shift 2 ;;
    -model) MODEL_NAME="$2"; shift 2 ;;
    -with-logs) WITH_LOGS=1; shift 1 ;;
    -research) PHASE="RESEARCH"; shift ;;
    -design) PHASE="DESIGN"; shift ;;
    -implement) PHASE="IMPLEMENT"; shift ;;
    -test) PHASE="TEST"; shift ;;
    -review) PHASE="REVIEW"; shift ;;
    -publish-obsidian) PHASE="PUBLISH_OBSIDIAN"; shift ;;
    *) break ;;
  esac
done


if [ -z "$PHASE" ]; then
  echo "Error: Phase (-research, -design, -implement, -test, -review, -publish-obsidian) must be specified."
  exit 1
fi

TASKS=("$@")

# ==========================================
# 複数タスクが指定された場合（自動的に並列ワークツリー実行）
# ==========================================
if [ ${#TASKS[@]} -gt 1 ]; then
  echo "🚀 [並列モード] ${#TASKS[@]} 個のタスクを $PHASE フェーズで並列実行します..."
  CURRENT_BRANCH=$(git branch --show-current)
  if [ -z "$CURRENT_BRANCH" ]; then
    echo "エラー: 現在のブランチが特定できません。"
    exit 1
  fi

  for i in "${!TASKS[@]}"; do
    TASK_TEXT="${TASKS[$i]}"
    BRANCH_NAME="${CURRENT_BRANCH}-task-$i"
    WORKTREE_DIR="../${REPO_DIR}-task-$i"

    echo "🌱 ワークツリーを作成: $WORKTREE_DIR (Branch: $BRANCH_NAME)"
    git worktree add -b "$BRANCH_NAME" "$WORKTREE_DIR" "$CURRENT_BRANCH" 2>/dev/null || git worktree add "$WORKTREE_DIR" "$BRANCH_NAME" 2>/dev/null

    (
      cd "$WORKTREE_DIR"
      echo "  👉 タスク開始: $TASK_TEXT"
      ARGS=("-to" "$ORIGINAL_AI")
      if [ -n "$MODEL_NAME" ]; then ARGS+=("-model" "$MODEL_NAME"); fi
      if [ "$WITH_LOGS" -eq 1 ]; then ARGS+=("-with-logs"); fi
      
      if [ "$PHASE" = "PUBLISH_OBSIDIAN" ]; then
        PHASE_FLAG="-publish-obsidian"
      else
        PHASE_FLAG="-$(echo "$PHASE" | tr '[:upper:]' '[:lower:]')"
      fi
      "$0" "${ARGS[@]}" "$PHASE_FLAG" "$TASK_TEXT" < /dev/null > ".ai-task.log" 2>&1
      echo "  ✅ タスク完了 (Branch: $BRANCH_NAME)"
    ) &
  done
  
  echo "=========================================================="

  echo "⏳ すべてのエージェントの完了を待機しています..."
  wait

  echo "🔄 自動マージとクリーンアップを開始します..."
  for i in "${!TASKS[@]}"; do
    BRANCH_NAME="${CURRENT_BRANCH}-task-$i"
    WORKTREE_DIR="../${REPO_DIR}-task-$i"
    
    (
      cd "$WORKTREE_DIR"
      if [[ -n $(git status -s) ]]; then
        git add .
        git commit -m "[AUTO-SAVE] $PHASE: ${TASKS[$i]}"
      fi
    )
    
    if git merge "$BRANCH_NAME" -m "Merge parallel task $i"; then
      echo "  ✅ マージ成功: $BRANCH_NAME"
      git worktree remove -f "$WORKTREE_DIR" 2>/dev/null || true
      git branch -D "$BRANCH_NAME" 2>/dev/null || true
    else
      echo "  ⚠️ コンフリクト発生: $BRANCH_NAME の自動マージに失敗しました。手動で確認してください。"
    fi
  done
  echo "=========================================================="
  exit 0
fi

# ==========================================
# 単一タスクモード（従来通りの実行）
# ==========================================
TASK_DESC="${TASKS[0]}"
PROMPT_PREFIX=""
AI_BASE="${CMD_ARRAY[0]}"

if [ -n "$MODEL_NAME" ]; then
  CMD_ARRAY+=(--model "$MODEL_NAME")
fi

if [[ "$AI_BASE" == *"claude"* ]]; then
  CMD_ARRAY+=(-p)
elif [[ "$AI_BASE" == *"codex"* ]]; then
  CMD_ARRAY=("codex" "exec")
  if [ -n "$MODEL_NAME" ]; then
    CMD_ARRAY+=(--model "$MODEL_NAME")
  fi
fi

if [ "$PHASE" = "RESEARCH" ]; then
  echo "🔍 [RESEARCH フェーズ] 調査・アイデア出しを開始します..."
  if [[ "$AI_BASE" == *"codex"* ]]; then
    CMD_ARRAY+=(--dangerously-bypass-approvals-and-sandbox)
  elif [[ "$AI_BASE" == *"claude"* ]] || [[ "$AI_BASE" == *"agy"* ]]; then
    CMD_ARRAY+=(--dangerously-skip-permissions)
  fi
  PROMPT_PREFIX="【RESEARCHフェーズ】あなたは現在リサーチャーです。既存のコードやシステムを深く分析し、アイデア出しや課題解決の相談に乗ってください。コード本体は変更せず、調査結果や提案を必ず分かりやすいMarkdownファイル（例: docs/research_idea_xxx.md）にまとめて保存し、コミットして終了してください。"

elif [ "$PHASE" = "DESIGN" ]; then
  if [[ "$AI_BASE" == *"codex"* ]]; then
    CMD_ARRAY+=(--dangerously-bypass-approvals-and-sandbox)
  fi
  echo "📐 [DESIGN フェーズ] 設計タスクを開始します..."
  if [[ "$AI_BASE" == *"claude"* ]] || [[ "$AI_BASE" == *"agy"* ]]; then
    CMD_ARRAY+=(--dangerously-skip-permissions)
  fi
  PROMPT_PREFIX="【DESIGNフェーズ】要件に基づいて設計を行い、結果を必ず docs/design.md 等のMarkdownファイルとして作成・保存してください。設計の際は必ずリポジトリ内の docs/AI_DESIGN_RULES.md (および固有プロファイルが存在する場合はそれ) のルールを熟読し、厳守してアーキテクチャを取捨選択してください。その際、ファイル名は「タスク内容が人間にも一目で分かる具体的な英数字の名前（例: docs/design_ollama_setup.md）」をあなた自身で考えて命名してください。その後、実装者に向けて空コミット (git commit --allow-empty -m \"IMPLEMENT: <次の指示>\") を作成して終了してください。"

elif [ "$PHASE" = "IMPLEMENT" ]; then
  echo "🔨 [IMPLEMENT フェーズ] 実装タスクを開始します..."
  if ! git log -n 5 --oneline | grep -iqE "DESIGN|design"; then
    echo "❌ [安全装置発動] 直近のGit履歴に設計(DESIGN)の痕跡がありません。まずは -design フェーズで要件定義を行ってください。"
    exit 1
  fi
  if [[ "$AI_BASE" == *"codex"* ]]; then
    CMD_ARRAY+=(--dangerously-bypass-approvals-and-sandbox)
  elif [[ "$AI_BASE" == *"claude"* ]] || [[ "$AI_BASE" == *"agy"* ]]; then
    CMD_ARRAY+=(--dangerously-skip-permissions)
  fi
  PROMPT_PREFIX="【IMPLEMENTフェーズ】設計書と最新の空コミット(IMPLEMENT)の指示に従って実装を行ってください。完了したら実装完了コミットを作成して終了してください。"

elif [ "$PHASE" = "TEST" ]; then
  echo "🧪 [TEST フェーズ] 受入試験・動作確認を開始します..."
  if [[ "$AI_BASE" == *"codex"* ]]; then
    CMD_ARRAY+=(--dangerously-bypass-approvals-and-sandbox)
  elif [[ "$AI_BASE" == *"claude"* ]] || [[ "$AI_BASE" == *"agy"* ]]; then
    CMD_ARRAY+=(--dangerously-skip-permissions)
  fi
  
  LOG_INSTRUCTION="そこまでの結果とエラー原因の考察を docs/test_report_xxx.md にまとめて保存し"
  if [ "$WITH_LOGS" -eq 1 ]; then
    LOG_INSTRUCTION="実行したコマンドの生のログ（標準出力・標準エラー出力）を絶対に要約・省略せずすべてそのまま docs/test_report_xxx.md 等に記録し、そこまでの結果とエラー原因の考察も併記して保存し"
  fi
  
  PROMPT_PREFIX="【TESTフェーズ】あなたはテストエンジニアです。実際の環境でコマンドを実行し動作確認を行ってください。※重要※ コマンド実行時にエラーが出た場合、それが『システムの不具合』なのか『あなたが打ったコマンドの文法ミス・環境固有のパス違い等』なのかを判断し、あなたのミスであれば自己修正して再試行してください。システムの不具合（合格条件を満たさない等）であれば、直ちに実行を中止し、${LOG_INSTRUCTION}、コミットして終了してください。"

elif [ "$PHASE" = "REVIEW" ]; then
  echo "👀 [REVIEW フェーズ] レビューを開始します..."
  if [[ "$AI_BASE" == *"codex"* ]]; then
    CMD_ARRAY+=(--dangerously-bypass-approvals-and-sandbox)
  elif [[ "$AI_BASE" == *"claude"* ]] || [[ "$AI_BASE" == *"agy"* ]]; then
    CMD_ARRAY+=(--dangerously-skip-permissions)
  fi
  PROMPT_PREFIX="【REVIEWフェーズ】あなたは現在レビュアーです。基本的には既存のコードを変更せず、最新の差分(git diff)を分析・レビューしてください。レビュー結果（指摘事項や改善案）はターミナルではなく、「レビュー対象が人間にも一目で分かる具体的なファイル名（例: docs/review_ollama_setup.md）」を自分で考えてMarkdownファイルに書き出して保存し、それをコミットして終了してください。"

elif [ "$PHASE" = "PUBLISH_OBSIDIAN" ]; then
  echo "📚 [PUBLISH_OBSIDIAN フェーズ] 人間確認用の要約をObsidianへ作成します..."
  if [[ "$AI_BASE" == *"codex"* ]]; then
    CMD_ARRAY+=(--dangerously-bypass-approvals-and-sandbox)
  elif [[ "$AI_BASE" == *"claude"* ]] || [[ "$AI_BASE" == *"agy"* ]]; then
    CMD_ARRAY+=(--dangerously-skip-permissions)
  fi
  OBSIDIAN_DIR="/home/tanida/Obsidian-Win/Projects/${REPO_DIR}"
  mkdir -p "$OBSIDIAN_DIR"
  PROMPT_PREFIX="【PUBLISH_OBSIDIANフェーズ】人間が状況を確認して判断するための要約ノートを、必ず ${OBSIDIAN_DIR}/ に新規Markdownファイルとして作成してください。コード、設定、テスト、生ログのコピーは作成しません。目的・対象範囲・現在の状態・確認済みの証拠・重要な判断と未解決事項・次のアクションを簡潔に記し、参照したコミットSHAと実装リポジトリ内の関連パスを明記してください。Obsidianのノートは人間向けの要約であり、実装上の正本はこのGitリポジトリです。実装リポジトリ内のファイルは変更せず、ObsidianノートをGitへコミットしようともしないでください。"
fi

if [ -n "$TASK_DESC" ] && [ "$PHASE" != "PUBLISH_OBSIDIAN" ]; then
  git commit --allow-empty -m "${PHASE}: $TASK_DESC"
fi

echo "🚀 ${CMD_ARRAY[0]} にバトンを渡します..."

PROMPT="
$PROMPT_PREFIX

現在の状況を把握するために、以下のGit情報を確認してください：
1. \`git log -n 3\` （直近のコミットメッセージと意図の確認）
2. \`git status\` （未コミットの変更の確認）
3. \`git diff HEAD\` （最新の差分確認）
4. ナレッジベース: \`/home/tanida/Obsidian-Win/Projects/${REPO_DIR}/\` 配下のMarkdown文書（過去の設計、議事録、要件など）

上記から前任者が残した意図を読み取り、フェーズの目的に沿って作業を進めてください。

【重要ルール】
作業完了後にGitコミットを作成する際、コミットメッセージは必ず「[by ${AI_BASE}] ${PHASE}: <メッセージ>」の形式にしてください。
"

if [[ "$AI_BASE" == *"agy"* ]]; then
  "${CMD_ARRAY[@]}" -p "$PROMPT"
else
  "${CMD_ARRAY[@]}" "$PROMPT"
fi
