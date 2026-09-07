# Helpers sourced by vset / xelab / xsim. Do not run this file.

: "${MMU_SIM_SCRIPTS:=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
: "${MMU_SIM_REPO:=$(cd "$MMU_SIM_SCRIPTS/../.." && pwd)}"
MMU_SIM_OUT=$MMU_SIM_REPO/sim/work
MMU_SIM_DUMP=$MMU_SIM_REPO/sim/internal
: "${MMU_SIM_VARIANT:=mmu_branch_v1}"
: "${MMU_SIM_TIME:=1ms}"
: "${MMU_SIM_PART:=xc7a35tcpg236-1}"

set_sim_variant() {
  local v=$1
  v=${v%$'\r'}
  v=${v%/}
  [[ -n "$v" ]] || return 1
  v=$(basename "$v")
  if [[ ! -d "$MMU_SIM_REPO/rtl/$v" ]]; then
    echo "Unknown RTL variant '$v' (expected a directory under rtl/)." >&2
    echo "Available:" >&2
    local d
    for d in "$MMU_SIM_REPO"/rtl/*/; do
      [[ -d "$d" ]] || continue
      echo "  $(basename "$d")" >&2
    done
    return 1
  fi
  MMU_SIM_VARIANT=$v
}

require_vset() {
  if [[ "${MMU_VSET:-}" != 1 ]]; then
    echo "source sim/scripts/vset first" >&2
    return 1
  fi
  if [[ -z "${MMU_XVHDL:-}" || -z "${MMU_XELAB:-}" || -z "${MMU_XSIM:-}" ]]; then
    echo "vset did not finish; source sim/scripts/vset again" >&2
    return 1
  fi
}

to_win() {
  local p=$1
  if [[ "$p" =~ ^[A-Za-z]: ]]; then
    printf '%s' "$p"
    return
  fi
  if command -v wslpath >/dev/null 2>&1; then
    wslpath -w "$p"
  else
    printf '%s' "$p"
  fi
}

to_unix() {
  local p=$1
  p=${p%$'\r'}
  if [[ "$p" =~ ^[A-Za-z]: ]]; then
    wslpath -u "$p"
  else
    printf '%s' "$p"
  fi
}

to_tcl_path() {
  local p
  p=$(to_win "$1")
  printf '%s' "${p//\\//}"
}

is_windows_tool() {
  case "$1" in
    *.bat|*.cmd|*.exe) return 0 ;;
    /mnt/[a-zA-Z]/*) return 0 ;;
    *) return 1 ;;
  esac
}

normalize_name() {
  local n
  n=$(basename "$1")
  n=${n%.vhd}
  case "${n,,}" in
    top|processor_controller) printf '%s' Processor_Controller ;;
    mpu|multimedia_processor_unit) printf '%s' Multimedia_Processor_Unit ;;
    saturation_math) printf '%s' saturate_math ;;
    forward) printf '%s' forward_unit ;;
    *) printf '%s' "$n" ;;
  esac
}

compile_rank() {
  local n p
  n=$(basename "$1")
  n=${n,,}
  p=${1,,}
  p=${p//\\//}
  if [[ "$n" == *_tb.vhd ]]; then
    printf '5'
  elif [[ "$n" == numeric_var.vhd ]]; then
    printf '0'
  elif [[ "$p" == */ip/* ]]; then
    printf '1'
  elif [[ "$p" == *package* || "$p" == */generic/* || "$p" == */architecture/* || "$p" == */mmu_internal/* ]]; then
    printf '2'
  else
    printf '3'
  fi
}

walk_vhd() {
  local root=$1 skip_tb=${2:-0} f p
  [[ -d "$root" ]] || return 0
  while IFS= read -r -d '' f; do
    if [[ "$skip_tb" == 1 && "$(basename "$f")" == *_tb.vhd ]]; then
      continue
    fi
    # Duplicate ALU packages live under mmu_internal/; architecture/ is compiled.
    p=${f,,}
    p=${p//\\//}
    if [[ "$skip_tb" == 1 && "$p" == */mmu_internal/* ]]; then
      continue
    fi
    printf '%s\0' "$f"
  done < <(find "$root" \( -type d \( -name build -o -name work \) -prune \) -o -type f -name '*.vhd' -print0)
}

find_rtl_file() {
  local root=$1 raw=$2
  local cand n f p
  local names=() matches=()
  n=$(normalize_name "$raw")
  names+=("$n")
  case "${n,,}" in
    saturate_math) names+=(staturated_math) ;;
    unsigned_asm) names+=(unsiged_asm) ;;
    forward_unit) names+=(forward) ;;
  esac
  for cand in "${names[@]}"; do
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      p=${f,,}
      p=${p//\\//}
      [[ "$p" == */mmu_internal/* ]] && continue
      [[ "$p" == */verification/* ]] && continue
      matches+=("$f")
    done < <(find "$root" -type f -iname "${cand}.vhd" ! -iname '*_tb.vhd' 2>/dev/null)
  done
  if [[ ${#matches[@]} -eq 0 ]]; then
    return 1
  fi
  for f in "${matches[@]}"; do
    p=${f,,}
    p=${p//\\//}
    if [[ "$p" == */generic/* ]]; then
      printf '%s' "$f"
      return 0
    fi
  done
  printf '%s' "${matches[0]}"
}

vhd_work_deps() {
  local file=$1 line low
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line=${line%$'\r'}
    line=${line%%--*}
    low=${line,,}
    if [[ "$low" =~ use[[:space:]]+work\.([a-z0-9_]+) ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
    fi
    if [[ "$low" =~ entity[[:space:]]+work\.([a-z0-9_]+) ]]; then
      printf '%s\n' "${BASH_REMATCH[1]}"
    fi
  done < "$file"
}

find_tb_file() {
  local tb_root=$1 dut=$2 hint=${3:-} name h f
  local names=()
  if [[ -n "$hint" && "$hint" != "." && "$hint" != "none" ]]; then
    if [[ -f "$hint" ]]; then
      printf '%s' "$hint"
      return 0
    fi
    h=$(normalize_name "$hint")
    [[ "$h" == *_tb ]] || h=${h}_tb
    names+=("${h}.vhd")
  fi
  case "$dut" in
    Processor_Controller)
      names+=(Processor_Controller_tb.vhd)
      ;;
    Multimedia_Processor_Unit)
      names+=(Multimedia_Processor_Unit_tb.vhd Multimedia_Processor_Unit_tb_vivado.vhd)
      ;;
    saturate_math)
      names+=(saturation_math_tb.vhd saturate_math_tb.vhd)
      ;;
    *)
      names+=("${dut}_tb.vhd")
      ;;
  esac
  for name in "${names[@]}"; do
    f=$(find "$tb_root" -type f -name "$name" 2>/dev/null | head -n1)
    if [[ -n "$f" ]]; then
      printf '%s' "$f"
      return 0
    fi
  done
  return 1
}

collect_sources() {
  local rtl_root=$1 tb_root=$2 dut_in=$3 tb_hint=$4
  local dut tb_file dut_file f dep rf
  local -a queue=()
  local -A seen=()
  dut=$(normalize_name "$dut_in")
  if ! dut_file=$(find_rtl_file "$rtl_root" "$dut"); then
    echo "No RTL file for entity '$dut' under $rtl_root" >&2
    return 1
  fi
  if ! tb_file=$(find_tb_file "$tb_root" "$dut" "$tb_hint"); then
    echo "No testbench found for '$dut' under $tb_root" >&2
    return 1
  fi
  MMU_DUT=$dut
  MMU_TB_FILE=$tb_file
  MMU_TB_TOP=$(basename "$tb_file" .vhd)
  queue+=("$dut_file" "$tb_file")
  seen["$dut_file"]=1
  seen["$tb_file"]=1
  local i=0
  while (( i < ${#queue[@]} )); do
    f=${queue[i]}
    i=$((i + 1))
    while IFS= read -r dep; do
      [[ -n "$dep" ]] || continue
      if ! rf=$(find_rtl_file "$rtl_root" "$dep"); then
        continue
      fi
      [[ -z "${seen[$rf]:-}" ]] || continue
      seen[$rf]=1
      queue+=("$rf")
    done < <(vhd_work_deps "$f")
  done
  MMU_SRC_FILES=()
  while IFS=$'\t' read -r _ f; do
    [[ -n "$f" ]] || continue
    MMU_SRC_FILES+=("$f")
  done < <(
    for f in "${queue[@]}"; do
      printf '%s\t%s\n' "$(compile_rank "$f")" "$f"
    done | sort -n -k1,1
  )
  if [[ ${#MMU_SRC_FILES[@]} -eq 0 ]]; then
    echo "No VHDL for '$dut'" >&2
    return 1
  fi
  MMU_SNAP=${MMU_TB_TOP}_behav
}

write_prj() {
  local prj=$1 f rel
  mkdir -p "$(dirname "$prj")"
  {
    echo "# generated by sim/scripts; variant=$MMU_SIM_VARIANT dut=$MMU_DUT; do not edit"
    for f in "${MMU_SRC_FILES[@]}"; do
      if is_windows_tool "${MMU_XVHDL:-}"; then
        rel=$(to_tcl_path "$f")
      else
        rel=$f
      fi
      printf 'vhdl work "%s"\n' "$rel"
    done
  } > "$prj"
}

find_license_file() {
  local c unix
  local candidates=()
  if [[ -n "${MMU_LICENSE_ARG:-}" ]]; then
    candidates+=("$MMU_LICENSE_ARG")
  fi
  candidates+=(
    "/mnt/c/Xilinx/Xilinx.lic"
    "/mnt/c/Xilinx/licenses/Xilinx.lic"
    "$HOME/.Xilinx/Xilinx.lic"
  )
  for c in /mnt/c/Users/*/AppData/Roaming/XilinxLicense/Xilinx.lic; do
    candidates+=("$c")
  done
  for c in "${candidates[@]}"; do
    [[ -z "$c" ]] && continue
    case "$c" in
      *@*) continue ;;
    esac
    c=${c%%;*}
    unix=$c
    if [[ "$c" =~ ^[A-Za-z]: ]]; then
      unix=$(to_unix "$c")
    fi
    if [[ -f "$unix" ]]; then
      MMU_LICENSE_FILE=$unix
      return 0
    fi
  done
  MMU_LICENSE_FILE=""
  return 1
}

resolve_vivado_root() {
  local c=$1
  [[ -z "$c" ]] && return 1
  if [[ -d "$c/bin" ]]; then
    printf '%s' "$c"
    return 0
  fi
  if [[ -f "$c" ]]; then
    printf '%s' "$(cd "$(dirname "$c")/.." && pwd)"
    return 0
  fi
  return 1
}

find_vivado_env() {
  local hit root c
  if [[ -n "${MMU_VIVADO_ARG:-}" ]]; then
    if root=$(resolve_vivado_root "$MMU_VIVADO_ARG"); then
      MMU_VIVADO_ROOT=$root
    else
      echo "Vivado not found: $MMU_VIVADO_ARG" >&2
      return 1
    fi
  elif [[ -n "${MMU_VIVADO_ROOT:-}" && -d "$MMU_VIVADO_ROOT/bin" ]]; then
    :
  else
    MMU_VIVADO_ROOT=""
    if command -v vivado >/dev/null 2>&1; then
      hit=$(command -v vivado)
      case "$hit" in
        /mnt/[a-zA-Z]/*) ;;
        *) MMU_VIVADO_ROOT=$(cd "$(dirname "$hit")/.." && pwd) ;;
      esac
    fi
    if [[ -z "$MMU_VIVADO_ROOT" ]]; then
      for c in \
        /opt/Xilinx/Vivado/*/settings64.sh \
        /tools/Xilinx/Vivado/*/settings64.sh \
        "$HOME/Xilinx/Vivado"/*/settings64.sh \
        /mnt/c/Xilinx/*/Vivado/settings64.bat \
        /mnt/c/Xilinx/Vivado/*/settings64.bat \
        /mnt/c/FPGA/*/Vivado/settings64.bat
      do
        [[ -f "$c" ]] || continue
        MMU_VIVADO_ROOT=$(cd "$(dirname "$c")" && pwd)
        break
      done
    fi
  fi
  if [[ -z "${MMU_VIVADO_ROOT:-}" || ! -d "$MMU_VIVADO_ROOT/bin" ]]; then
    echo "Vivado not found. Pass -Vivado /mnt/c/Xilinx/2026.1/Vivado" >&2
    return 1
  fi
  MMU_VIVADO_BIN=$MMU_VIVADO_ROOT/bin
  case "$MMU_VIVADO_ROOT" in
    /mnt/[a-zA-Z]/*)
      # Windows install seen from WSL: never source settings64.sh (it uses c:\ paths).
      if [[ -f "$MMU_VIVADO_ROOT/settings64.bat" ]]; then
        MMU_VIVADO_SETTINGS=$MMU_VIVADO_ROOT/settings64.bat
      else
        MMU_VIVADO_SETTINGS=""
      fi
      MMU_XVHDL=$MMU_VIVADO_BIN/xvhdl.bat
      MMU_XELAB=$MMU_VIVADO_BIN/xelab.bat
      MMU_XSIM=$MMU_VIVADO_BIN/xsim.bat
      ;;
    *)
      if [[ -f "$MMU_VIVADO_ROOT/settings64.sh" ]]; then
        MMU_VIVADO_SETTINGS=$MMU_VIVADO_ROOT/settings64.sh
      else
        MMU_VIVADO_SETTINGS=""
      fi
      if [[ -f "$MMU_VIVADO_BIN/xvhdl" ]]; then
        MMU_XVHDL=$MMU_VIVADO_BIN/xvhdl
        MMU_XELAB=$MMU_VIVADO_BIN/xelab
        MMU_XSIM=$MMU_VIVADO_BIN/xsim
      else
        MMU_XVHDL=$MMU_VIVADO_BIN/xvhdl.bat
        MMU_XELAB=$MMU_VIVADO_BIN/xelab.bat
        MMU_XSIM=$MMU_VIVADO_BIN/xsim.bat
      fi
      ;;
  esac
  find_license_file || true
  return 0
}

harvest_dumps() {
  local name dest=$MMU_SIM_DUMP found
  mkdir -p "$dest"
  for name in register_file.txt buffer_file.txt tsb_buffer.txt out_buffer.txt; do
    if [[ -f "$MMU_SIM_OUT/$name" ]]; then
      mv -f "$MMU_SIM_OUT/$name" "$dest/$name"
      continue
    fi
    found=$(find "$MMU_SIM_OUT" -type f -name "$name" 2>/dev/null | head -n1)
    if [[ -n "$found" ]]; then
      mv -f "$found" "$dest/$name"
    fi
  done
}

# Detach the XSim GUI. On Windows, never quote xsim.bat together with a quoted
# argument: cmd's START concatenates them into one invalid command.
# Run XSim GUI in this terminal (no extra cmd window). Blocks until the GUI closes.
start_xsim_gui() {
  local log=$1
  shift
  mkdir -p "$MMU_SIM_OUT"
  if is_windows_tool "$MMU_XSIM"; then
    MMU_XILINX_FG=1 run_xilinx_cmd "$log" "xsim.bat $*"
  else
    (cd "$MMU_SIM_OUT" && "$MMU_XSIM" "$@")
  fi
}

fail_from_log() {
  local log=$1
  [[ -f "$log" ]] || return 1
  if grep -qi "license was not found" "$log"; then
    cat "$log"
    echo "Vivado/XSim rejected the license file." >&2
    return 0
  fi
  if grep -qiE "ERROR:|fatal run-time error|\[Simulator 45-1\]" "$log"; then
    cat "$log"
    return 0
  fi
  return 1
}

run_xilinx_cmd() {
  local log=$1
  shift
  local rc=0
  mkdir -p "$MMU_SIM_OUT"
  if is_windows_tool "$MMU_XVHDL"; then
    local launch=$MMU_SIM_OUT/run_xilinx.cmd
    local settings_win out_win lic_win cmdline
    out_win=$(to_win "$MMU_SIM_OUT")
    {
      printf '@echo off\r\n'
      printf 'setlocal\r\n'
      if [[ -n "$MMU_VIVADO_SETTINGS" && -f "$MMU_VIVADO_SETTINGS" ]]; then
        settings_win=$(to_win "$MMU_VIVADO_SETTINGS")
        printf 'call "%s"\r\n' "$settings_win"
      fi
      if [[ -n "${MMU_LICENSE_FILE:-}" ]]; then
        lic_win=$(to_win "$MMU_LICENSE_FILE")
        printf 'set "XILINXD_LICENSE_FILE=%s"\r\n' "$lic_win"
        printf 'set "LM_LICENSE_FILE=%s"\r\n' "$lic_win"
      fi
      printf 'cd /d "%s"\r\n' "$out_win"
      # Nested .bat tools must be CALLed or cmd never returns (and PATH can drop).
      cmdline=$*
      case "$cmdline" in
        [cC][aA][lL][lL]\ *|[sS][tT][aA][rR][tT]\ *) ;;
        *) cmdline="call $cmdline" ;;
      esac
      printf '%s\r\n' "$cmdline"
      printf 'exit /b %%ERRORLEVEL%%\r\n'
    } > "$launch"
    if [[ "${MMU_XILINX_FG:-}" == 1 ]]; then
      cmd.exe /c "$(to_win "$launch")" 2>&1 | tee "$log"
      rc=${PIPESTATUS[0]}
    else
      cmd.exe /c "$(to_win "$launch")" > "$log" 2>&1
      rc=$?
    fi
  else
    if [[ -n "${MMU_LICENSE_FILE:-}" ]]; then
      export XILINXD_LICENSE_FILE=$MMU_LICENSE_FILE
      export LM_LICENSE_FILE=$MMU_LICENSE_FILE
    fi
    (cd "$MMU_SIM_OUT" && "$@") > "$log" 2>&1
    rc=$?
  fi
  return "$rc"
}

xilinx_bat_name() {
  local p=$1
  printf '%s' "$(basename "$p")"
}

# Called only from vset. Finds Vivado and exports the live session flag.
mmu_vset() {
  if ! set_sim_variant "${MMU_SIM_VARIANT:-mmu_simple_v2}"; then
    return 1
  fi
  if ! find_vivado_env; then
    return 1
  fi
  if [[ -n "$MMU_VIVADO_SETTINGS" && "$MMU_VIVADO_SETTINGS" == *.sh ]]; then
    case "$MMU_VIVADO_ROOT" in
      /mnt/[a-zA-Z]/*) ;;
      *)
        # shellcheck disable=SC1090
        source "$MMU_VIVADO_SETTINGS"
        ;;
    esac
  fi
  MMU_SIM_OUT=$MMU_SIM_REPO/sim/work
  MMU_SIM_DUMP=$MMU_SIM_REPO/sim/internal
  export MMU_SIM_SCRIPTS MMU_SIM_REPO MMU_SIM_OUT MMU_SIM_DUMP
  export MMU_SIM_VARIANT MMU_SIM_TIME MMU_SIM_PART
  export MMU_VIVADO_ROOT MMU_VIVADO_BIN MMU_VIVADO_SETTINGS
  export MMU_XVHDL MMU_XELAB MMU_XSIM
  export MMU_LICENSE_FILE
  export MMU_VSET=1
  export PATH="$MMU_SIM_SCRIPTS:$PATH"
}
