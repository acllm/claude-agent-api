#!/bin/bash
# update-llm.sh
# 修改 claude-agent-api 的 LLM Provider 配置并重启 Pod
#
# 用法:
#   ./scripts/update-llm.sh                          # 交互式
#   ./scripts/update-llm.sh --base-url "https://..."  # 命令行参数
#   ./scripts/update-llm.sh --api-key "sk-ant-..."    # 注入 API Key (K8s Secret)
#
# LLM 配置渲染路径:
#   values.yaml                   → Helm 值文件
#     └── llm.baseUrl             → $ANTHROPIC_BASE_URL
#     └── llm.models.haiku.id     → $ANTHROPIC_DEFAULT_HAIKU_MODEL
#     └── llm.models.sonnet.id    → $ANTHROPIC_DEFAULT_SONNET_MODEL
#     └── llm.models.opus.id      → $ANTHROPIC_DEFAULT_OPUS_MODEL
#     └── llm.assumeFirstParty    → $CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL
#     └── llm.enableToolSearch    → $ENABLE_TOOL_SEARCH
#
#   API Key 不在 Helm Chart 中注入（精简设计）。
#   每次 API 请求携带 apiKey 和可选 apiBaseUrl。
#   如需全局默认 API Key，通过 K8s Secret 注入环境变量:
#     kubectl create secret generic claude-agent-api-key \
#       --from-literal=api-key="sk-ant-..."

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CHART_DIR="$PROJECT_DIR/charts/claude-agent-api"
NAMESPACE="claude-agent"
RELEASE="claude-agent-api"

red()  { echo -e "\033[31m$*\033[0m"; }
green(){ echo -e "\033[32m$*\033[0m"; }
blue() { echo -e "\033[34m$*\033[0m"; }
cyan() { echo -e "\033[36m$*\033[0m"; }

# ============================================
# 解析参数
# ============================================
BASE_URL=""
MODEL_HAIKU=""
MODEL_SONNET=""
MODEL_OPUS=""
API_KEY=""
API_KEY_SECRET_NAME="claude-agent-api-key"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url)      BASE_URL="$2"; shift 2 ;;
    --model-haiku)   MODEL_HAIKU="$2"; shift 2 ;;
    --model-sonnet)  MODEL_SONNET="$2"; shift 2 ;;
    --model-opus)    MODEL_OPUS="$2"; shift 2 ;;
    --api-key)       API_KEY="$2"; shift 2 ;;
    --help|-h)
      echo "用法: $0 [选项]"
      echo ""
      echo "LLM Provider 配置:"
      echo "  --base-url URL        LLM API 代理地址"
      echo "  --model-haiku ID      Haiku 模型 ID"
      echo "  --model-sonnet ID     Sonnet 模型 ID"
      echo "  --model-opus ID       Opus 模型 ID"
      echo ""
      echo "API Key 管理:"
      echo "  --api-key KEY         创建/更新 K8s Secret 存储 API Key"
      echo "                        注意: API Key 由每次请求携带，这是全局默认值"
      echo ""
      exit 0
      ;;
    *) red "未知参数: $1"; exit 1 ;;
  esac
done

# ============================================
# 显示当前配置
# ============================================
show_current() {
  blue ">>> 当前 Helm Release 配置"
  echo ""
  helm get values "$RELEASE" -n "$NAMESPACE" 2>/dev/null | \
    python3 -c "
import sys, yaml
try:
    d = yaml.safe_load(sys.stdin) or {}
    llm = d.get('llm', {})
    models = llm.get('models', {})
    print(f'  baseUrl:          {llm.get(\"baseUrl\", \"\")}')
    print(f'  haiku:            {models.get(\"haiku\", {}).get(\"id\", \"\")}  ({models.get(\"haiku\", {}).get(\"description\", \"\")})')
    print(f'  sonnet:           {models.get(\"sonnet\", {}).get(\"id\", \"\")}  ({models.get(\"sonnet\", {}).get(\"description\", \"\")})')
    print(f'  opus:             {models.get(\"opus\", {}).get(\"id\", \"\")}  ({models.get(\"opus\", {}).get(\"description\", \"\")})')
    print(f'  assumeFirstParty: {llm.get(\"assumeFirstParty\", \"\")}')
    print(f'  enableToolSearch: {llm.get(\"enableToolSearch\", \"\")}')
except Exception as e:
    print(f'  (无法解析: {e})')
" 2>/dev/null || echo "  (Release 不存在或无配置)"

  # 检查 API Key Secret
  echo ""
  if kubectl get secret "$API_KEY_SECRET_NAME" -n "$NAMESPACE" &>/dev/null; then
    green "  API Key Secret: $API_KEY_SECRET_NAME (已存在)"
  else
    cyan "  API Key Secret: 未创建 (每次请求手动携带 apiKey)"
  fi
  echo ""
}

# ============================================
# 交互式配置
# ============================================
interactive_config() {
  read -p "  baseUrl [$BASE_URL]: " input
  BASE_URL="${input:-$BASE_URL}"

  read -p "  Haiku Model ID [$MODEL_HAIKU]: " input
  MODEL_HAIKU="${input:-$MODEL_HAIKU}"

  read -p "  Sonnet Model ID [$MODEL_SONNET]: " input
  MODEL_SONNET="${input:-$MODEL_SONNET}"

  read -p "  Opus Model ID [$MODEL_OPUS]: " input
  MODEL_OPUS="${input:-$MODEL_OPUS}"
}

# ============================================
# 构建 Helm 参数
# ============================================
build_helm_args() {
  local args=""
  [[ -n "$BASE_URL" ]]     && args="$args --set llm.baseUrl=\"$BASE_URL\""
  [[ -n "$MODEL_HAIKU" ]]  && args="$args --set llm.models.haiku.id=\"$MODEL_HAIKU\""
  [[ -n "$MODEL_SONNET" ]] && args="$args --set llm.models.sonnet.id=\"$MODEL_SONNET\""
  [[ -n "$MODEL_OPUS" ]]   && args="$args --set llm.models.opus.id=\"$MODEL_OPUS\""
  [[ -n "$API_KEY" ]]       && args="$args --set llm.apiKey=\"$API_KEY\""
  echo "$args"
}

# ============================================
# 主流程
# ============================================
show_current

# 交互式
if [[ -z "$BASE_URL" && -z "$MODEL_HAIKU" && -z "$MODEL_SONNET" && -z "$MODEL_OPUS" && -z "$API_KEY" ]]; then
  blue ">>> 交互式配置（按 Enter 跳过不变）"
  interactive_config
fi

HELM_ARGS=$(build_helm_args)

# 更新 llm.apiKey（通过 Helm values，直接注入 Pod 环境变量）
if [[ -n "$API_KEY" ]]; then
  blue ">>> 更新 API Key（Helm values llm.apiKey → Pod ANTHROPIC_API_KEY）"
  HELM_ARGS="$HELM_ARGS --set llm.apiKey=\"$API_KEY\""
fi

# 更新 LLM 配置
if [[ -n "$HELM_ARGS" ]]; then
  blue ">>> 更新 LLM 配置"
  echo "  helm upgrade $RELEASE $CHART_DIR -n $NAMESPACE$HELM_ARGS"
  eval "helm upgrade $RELEASE $CHART_DIR -n $NAMESPACE $HELM_ARGS"
  green "  LLM 配置已更新"
fi

# 重启 Pod
if [[ -n "$HELM_ARGS" || -n "$API_KEY" ]]; then
  blue ">>> 重启 Pod"
  kubectl rollout restart deployment/"$RELEASE" -n "$NAMESPACE"
  kubectl rollout status deployment/"$RELEASE" -n "$NAMESPACE" --timeout=60s
  green "  Pod 已重启，新配置生效"
else
  cyan "  无变更，跳过重启"
fi

show_current
green "完成"