#!/usr/bin/env bash
#
# install-medpen-tools.sh
# -----------------------------------------------------------------------------
# MedPen Methodology — SaMD/SiMD 침투 테스트 툴 자동 설치 스크립트
#
# 이 Kali 시스템(kali-tools-top10 기준)에서 확인된 "미설치 권장 툴"을 설치합니다.
# 승인된 보안 평가 환경에서만 사용하세요.
#
# 사용법:
#   ./install-medpen-tools.sh [옵션]
#
# 옵션:
#   (옵션 없음)      핵심 툴(apt + pipx)만 설치 — 권장 기본값
#   --with-meta      의료기기 평가용 메타패키지까지 설치 (수 GB, 시간 소요)
#   --meta-only      메타패키지만 설치
#   --apt-only       apt 패키지만 설치 (pipx 건너뜀)
#   --pipx-only      pipx 패키지만 설치 (apt 건너뜀)
#   --dry-run        실제 설치 없이 수행할 작업만 출력
#   -y, --yes        확인 프롬프트 없이 진행
#   -h, --help       도움말
# -----------------------------------------------------------------------------
set -uo pipefail

# ---------- 설정: 설치 대상 ----------
# apt 저장소에서 설치 (패키지명 → 설치 확인용 명령)
APT_TOOLS=(
  "dcmtk:echoscu"        # DICOM 툴킷 (storescu/findscu/echoscu)
  "apktool:apktool"      # 안드로이드 APK 디컴파일/리빌드
  "jadx:jadx"            # Dalvik → Java 디컴파일
  "ghidra:ghidra"        # NSA 역공학 스위트
  "can-utils:candump"    # CAN 버스 송수신 (candump/cansend)
  "trivy:trivy"          # SBOM 생성 + 취약점 스캔 (FDA SBOM 요구)
  "syft:syft"            # SBOM 생성 (SPDX/CycloneDX)
)

# pipx로 설치 (apt에 없음). 일반 사용자 권한으로 설치됨.
PIPX_TOOLS=(
  "frida-tools:frida"        # 동적 계측 / 핀닝 우회 (모바일 SaMD)
  "volatility3:vol"          # 메모리 포렌식
  "objection:objection"      # Frida 기반 런타임 모바일 탐색
  "cyclonedx-bom:cyclonedx-py" # CycloneDX SBOM 생성 (Python)
  "pip-audit:pip-audit"      # Python 의존성 취약점 감사
)

# 의료기기 평가 역량 보강용 메타패키지
META_PKGS=(
  kali-tools-reverse-engineering
  kali-tools-hardware
  kali-tools-sdr
  kali-tools-rfid
  kali-tools-bluetooth
  kali-tools-wireless
)

# ---------- 모드 플래그 ----------
DO_APT=1; DO_PIPX=1; DO_META=0; DRY=0; ASSUME_YES=0

for arg in "$@"; do
  case "$arg" in
    --with-meta) DO_META=1 ;;
    --meta-only) DO_META=1; DO_APT=0; DO_PIPX=0 ;;
    --apt-only)  DO_PIPX=0; DO_META=0 ;;
    --pipx-only) DO_APT=0;  DO_META=0 ;;
    --dry-run)   DRY=1 ;;
    -y|--yes)    ASSUME_YES=1 ;;
    -h|--help)   grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "알 수 없는 옵션: $arg (도움말: -h)"; exit 2 ;;
  esac
done

# ---------- 출력 헬퍼 ----------
c_g="\033[32m"; c_y="\033[33m"; c_r="\033[31m"; c_b="\033[36m"; c_0="\033[0m"
info(){ printf "${c_b}[*]${c_0} %s\n" "$*"; }
ok(){   printf "${c_g}[+]${c_0} %s\n" "$*"; }
warn(){ printf "${c_y}[!]${c_0} %s\n" "$*"; }
err(){  printf "${c_r}[x]${c_0} %s\n" "$*" >&2; }
run(){  if [ "$DRY" -eq 1 ]; then echo "    (dry-run) $*"; else eval "$*"; fi; }

# ---------- 집계 ----------
INSTALLED=(); SKIPPED=(); FAILED=()

# ---------- 사전 점검 ----------
if ! command -v apt-get >/dev/null 2>&1; then
  err "apt-get을 찾을 수 없습니다. 이 스크립트는 Debian/Kali 계열 전용입니다."; exit 1
fi

# sudo 준비 (apt/meta 작업에 필요)
SUDO=""
if [ "$DO_APT" -eq 1 ] || [ "$DO_META" -eq 1 ]; then
  if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo >/dev/null 2>&1; then SUDO="sudo";
    else err "root 권한 또는 sudo가 필요합니다."; exit 1; fi
  fi
fi

# pipx는 root가 아닌 실제 사용자로 실행해야 함
PIPX_USER="${SUDO_USER:-$(id -un)}"
pipx_run(){
  if [ "$(id -u)" -eq 0 ] && [ "$PIPX_USER" != "root" ]; then
    run "sudo -u '$PIPX_USER' env PATH=\"\$PATH\" pipx $*"
  else
    run "pipx $*"
  fi
}

echo
info "MedPen 툴 설치  |  apt=$DO_APT  pipx=$DO_PIPX  meta=$DO_META  dry-run=$DRY"
echo

if [ "$ASSUME_YES" -eq 0 ] && [ "$DRY" -eq 0 ]; then
  read -r -p "진행하시겠습니까? [y/N] " a
  case "$a" in y|Y|yes) ;; *) echo "취소되었습니다."; exit 0 ;; esac
fi

# ---------- apt 업데이트 ----------
if [ "$DO_APT" -eq 1 ] || [ "$DO_META" -eq 1 ]; then
  info "패키지 인덱스 갱신 중..."
  run "$SUDO apt-get update -qq" || warn "apt update 경고 — 계속 진행합니다."
fi

# ---------- apt 툴 설치 ----------
if [ "$DO_APT" -eq 1 ]; then
  echo; info "=== apt 핵심 툴 ==="
  for entry in "${APT_TOOLS[@]}"; do
    pkg="${entry%%:*}"; chk="${entry##*:}"
    if command -v "$chk" >/dev/null 2>&1; then
      ok "$pkg — 이미 설치됨 (건너뜀)"; SKIPPED+=("$pkg"); continue
    fi
    info "설치: $pkg"
    if run "$SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y -qq '$pkg'"; then
      if [ "$DRY" -eq 1 ] || command -v "$chk" >/dev/null 2>&1; then
        ok "$pkg 설치 완료"; INSTALLED+=("$pkg")
      else
        err "$pkg — 설치했으나 '$chk' 확인 실패"; FAILED+=("$pkg")
      fi
    else
      err "$pkg 설치 실패"; FAILED+=("$pkg")
    fi
  done
fi

# ---------- pipx 툴 설치 ----------
if [ "$DO_PIPX" -eq 1 ]; then
  echo; info "=== pipx 툴 (사용자: $PIPX_USER) ==="
  if ! command -v pipx >/dev/null 2>&1; then
    warn "pipx가 없습니다. 설치 시도..."
    run "$SUDO apt-get install -y -qq pipx" || { err "pipx 설치 실패 — pipx 단계를 건너뜁니다."; DO_PIPX=0; }
    [ "$DRY" -eq 0 ] && pipx_run "ensurepath" >/dev/null 2>&1 || true
  fi
fi
if [ "$DO_PIPX" -eq 1 ]; then
  for entry in "${PIPX_TOOLS[@]}"; do
    pkg="${entry%%:*}"; chk="${entry##*:}"
    if command -v "$chk" >/dev/null 2>&1; then
      ok "$pkg ($chk) — 이미 설치됨 (건너뜀)"; SKIPPED+=("$pkg"); continue
    fi
    info "설치: $pkg (pipx)"
    if pipx_run "install '$pkg'"; then
      ok "$pkg 설치 완료"; INSTALLED+=("$pkg")
    else
      err "$pkg 설치 실패"; FAILED+=("$pkg")
    fi
  done
fi

# ---------- 메타패키지 설치 ----------
if [ "$DO_META" -eq 1 ]; then
  echo; info "=== 의료기기 평가 메타패키지 (대용량) ==="
  for m in "${META_PKGS[@]}"; do
    if dpkg -s "$m" >/dev/null 2>&1; then
      ok "$m — 이미 설치됨 (건너뜀)"; SKIPPED+=("$m"); continue
    fi
    info "설치: $m"
    if run "$SUDO DEBIAN_FRONTEND=noninteractive apt-get install -y -qq '$m'"; then
      ok "$m 설치 완료"; INSTALLED+=("$m")
    else
      err "$m 설치 실패"; FAILED+=("$m")
    fi
  done
fi

# ---------- 요약 ----------
echo
echo "────────────────────────────────────────────"
info "설치 요약"
printf "  ${c_g}설치됨 :${c_0} %s\n" "${INSTALLED[*]:-(없음)}"
printf "  ${c_y}건너뜀 :${c_0} %s\n" "${SKIPPED[*]:-(없음)}"
printf "  ${c_r}실패   :${c_0} %s\n" "${FAILED[*]:-(없음)}"
echo "────────────────────────────────────────────"

if [ "${#FAILED[@]}" -gt 0 ]; then
  warn "실패 항목이 있습니다. 네트워크/저장소 설정을 확인한 뒤 재실행하세요 (멱등적이라 안전)."
  exit 1
fi
ok "완료. pipx 툴은 새 셸 또는 'source ~/.bashrc' 후 PATH에 반영됩니다."
