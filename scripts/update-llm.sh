#!/bin/bash
# 更新 claude-agent-api 的 LLM Provider 配置并重启 Pod
#
# 用法:
#   ./scripts/update-llm.sh                              # 交互式输入 apiKey
#   ./scripts/update-llm.sh --api-key "sk-ant-..."       # 更新 API Key
#   ./scripts/update-llm.sh --base-url "https://..."     # 更新代理地址
#   ./scripts/update-llm.sh --model "claude-sonnet-4-20250514"  # 更新模型
#
# 配置渲染路径:
#   llm.apiKey              → ANTHROPIC_API_KEY
#   llm.baseUrl             → ANTHROPIC_BASE_URL
#   llm.models.{tier}.id    → ANTHROPIC_DEFAULT_{TIER}_MODEL

set -euo pipefail

CHART="charts/claude-agent-api"
NAMESPACE="claude-agent"
RELEASE="claude-agent-api"

API_KEY=""
BASE_URL=""
MODEL=""

usage() {
  echo "用法: $0 [选项]"
  echo ""
  echo "  --api-key KEY    Anthropic API Key"
  echo "  --base-url URL   LLM API 端点"
  echo "  --model MODEL    模型 ID（同时设 haiku/sonnet/opus）"
  echo "  -h, --help       显示帮助"
  exit 0
}

# 解析参数
while [[ $# -gt 0 ]]; do
  case "$1" in
    --api-key)  API_KEY="$2"; shift 2 ;;
    --base-url) BASE_URL="$2"; shift 2 ;;
    --model)    MODEL="$2"; shift 2 ;;
    -h|--help)  usage ;;
    *) echo "未知参数: $1"; usage ;;
  esac
done

# 无参数 → 交互式输入 apiKey
if [[ -z "$API_KEY" && -z "$BASE_URL" && -z "$MODEL" ]]; then
  read -rp "API Key: " API_KEY
fi

# 构建 Helm --set 参数
SET_ARGS=""
[[ -n "$API_KEY" ]]  && SET_ARGS="$SET_ARGS --set llm.apiKey=\"$API_KEY\""
[[ -n "$BASE_URL" ]] && SET_ARGS="$SET_ARGS --set llm.baseUrl=\"$BASE_URL\""
if [[ -n "$MODEL" ]]; then
  SET_ARGS="$SET_ARGS --set llm.models.haiku.id=\"$MODEL\""
  SET_ARGS="$SET_ARGS --set llm.models.sonnet.id=\"$MODEL\""
  SET_ARGS="$SET_ARGS --set llm.models.opus.id=\"$MODEL\""
fi

if [[ -z "$SET_ARGS" ]]; then
  echo "无变更"
  exit 0
fi

# 执行
echo ">>> helm upgrade $RELEASE $CHART -n $NAMESPACE"
eval "helm upgrade $RELEASE $CHART -n $NAMESPACE $SET_ARGS"

echo ">>> 重启 Pod"
kubectl rollout restart deployment/"$RELEASE" -n "$NAMESPACE"
kubectl rollout status deployment/"$RELEASE" -n "$NAMESPACE" --timeout=60s

echo "完成"
