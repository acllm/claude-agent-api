#!/bin/bash
# build-and-push.sh
# 编译 claude-agent-api 并构建镜像推送至 K3s local-registry
#
# 用法:
#   ./scripts/build-and-push.sh              # 编译 + 构建 + 推送
#   ./scripts/build-and-push.sh --build-only  # 仅编译
#   ./scripts/build-and-push.sh --push-only   # 仅构建 + 推送（跳过编译）
#
# 前置条件:
#   - node 22+ (npm)
#   - kubectl 已配置指向目标 K3s 集群
#   - K3s local-registry 在 10.43.96.136:5000 运行

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SERVICE_DIR="$PROJECT_DIR/services/claude-agent-api"
NAMESPACE="claude-agent"
REGISTRY="10.43.96.136:5000"
IMAGE_NAME="claude-agent-api"
IMAGE_TAG="latest"
TAR_FILE="/tmp/claude-agent-api-app.tar.gz"

# 代理配置（K3s 节点拉取镜像必需）
PROXY_URL="${KANIKO_HTTP_PROXY:-}"
NO_PROXY="*.byted.org,127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,${REGISTRY%:*}"

MODE="${1:-build-and-push}"

red()  { echo -e "\033[31m$*\033[0m"; }
green(){ echo -e "\033[32m$*\033[0m"; }
blue() { echo -e "\033[34m$*\033[0m"; }

# ============================================
# Step 1: 编译 TypeScript
# ============================================
do_build() {
  blue ">>> Step 1: TypeScript 编译"
  cd "$SERVICE_DIR"
  npm install --silent
  npx tsc
  green "  编译完成"
}

# ============================================
# Step 2: 打包源码
# ============================================
do_pack() {
  blue ">>> Step 2: 打包源码"
  cd "$SERVICE_DIR"
  tar czf "$TAR_FILE" Dockerfile package.json tsconfig.json src/ dist/
  local size=$(ls -lh "$TAR_FILE" | awk '{print $5}')
  green "  打包完成: $TAR_FILE ($size)"
}

# ============================================
# Step 3: 上传至集群 PVC
# ============================================
do_upload() {
  blue ">>> Step 3: 上传源码至集群"

  # 创建 PVC（如果不存在）
  kubectl get pvc build-context -n "$NAMESPACE" &>/dev/null || \
    kubectl create -f - <<YAML
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: build-context
  namespace: $NAMESPACE
spec:
  accessModes: ["ReadWriteOnce"]
  resources: { requests: { storage: 1Gi } }
  storageClassName: local-path
YAML

  # 创建上传 Pod
  kubectl delete pod upload-source -n "$NAMESPACE" --ignore-not-found --grace-period=1
  kubectl run upload-source -n "$NAMESPACE" \
    --image=busybox:latest \
    --overrides='{
      "spec": {
        "containers": [{
          "name": "upload",
          "image": "busybox:latest",
          "command": ["sleep", "3600"],
          "volumeMounts": [{"name": "build-context", "mountPath": "/workspace"}]
        }],
        "volumes": [{"name": "build-context", "persistentVolumeClaim": {"claimName": "build-context"}}]
      }
    }'

  kubectl wait --for=condition=ready pod/upload-source -n "$NAMESPACE" --timeout=30s

  # 上传并解压
  kubectl cp "$TAR_FILE" "$NAMESPACE/upload-source:/workspace/source.tar.gz"
  kubectl exec -n "$NAMESPACE" upload-source -- sh -c \
    "cd /workspace && tar xzf source.tar.gz && rm source.tar.gz"

  kubectl delete pod upload-source -n "$NAMESPACE" --grace-period=1
  green "  上传完成"
}

# ============================================
# Step 4: Kaniko 构建并推送
# ============================================
do_kaniko() {
  blue ">>> Step 4: Kaniko 构建镜像"

  kubectl delete job build-claude-agent-api -n "$NAMESPACE" --ignore-not-found

  kubectl create -f - <<YAML
apiVersion: batch/v1
kind: Job
metadata:
  name: build-claude-agent-api
  namespace: $NAMESPACE
spec:
  backoffLimit: 3
  ttlSecondsAfterFinished: 300
  template:
    spec:
      containers:
        - name: kaniko
          image: gcr.io/kaniko-project/executor:latest
          args:
            - "--dockerfile=Dockerfile"
            - "--context=/workspace"
            - "--destination=${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
            - "--insecure"
            - "--skip-tls-verify"
            - "--cache=true"
          env:
            - name: HTTP_PROXY
              value: "$PROXY_URL"
            - name: HTTPS_PROXY
              value: "$PROXY_URL"
            - name: NO_PROXY
              value: "$NO_PROXY"
          volumeMounts:
            - name: build-context
              mountPath: /workspace
      restartPolicy: Never
      volumes:
        - name: build-context
          persistentVolumeClaim:
            claimName: build-context
YAML

  blue "  等待 Kaniko 构建完成..."
  kubectl wait --for=condition=complete job/build-claude-agent-api -n "$NAMESPACE" --timeout=600s
  green "  构建完成: ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

  # 清理
  kubectl delete job build-claude-agent-api -n "$NAMESPACE" --ignore-not-found
  kubectl delete pvc build-context -n "$NAMESPACE" --ignore-not-found
}

# ============================================
# Step 5: 重启 Pod（拉取新镜像 + 应用新配置）
# ============================================
do_restart() {
  blue ">>> Step 5: 重启 Pod"
  kubectl rollout restart deployment/claude-agent-api -n "$NAMESPACE"
  kubectl rollout status deployment/claude-agent-api -n "$NAMESPACE" --timeout=60s
  green "  Pod 已重启"
}

# ============================================
# 主流程
# ============================================
case "$MODE" in
  --build-only)
    do_build
    green "编译完成（未构建镜像）"
    ;;
  --push-only)
    do_pack
    do_upload
    do_kaniko
    do_restart
    green "全部完成"
    ;;
  *)
    do_build
    do_pack
    do_upload
    do_kaniko
    do_restart
    green "全部完成: 编译 → 构建 → 推送 → 重启"
    ;;
esac