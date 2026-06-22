#!/usr/bin/env bash
# ============================================================================
# ProxyHub node connectivity test script (§16)
#
# Usage:
#   bash test.sh tcp_ping <address> <port> <timeout> <tag>
#   echo '<json>' | bash test.sh url_test
# ============================================================================
set -o pipefail

# ------------------------------------------------------------------
# Python interpreter detection
# ------------------------------------------------------------------
PYTHON=""
for candidate in python3 python; do
    if command -v "$candidate" &>/dev/null; then
        if "$candidate" -c "import json" 2>/dev/null; then
            PYTHON="$candidate"
            break
        fi
    fi
done

if [ -z "$PYTHON" ]; then
    echo '{"success": false, "error": "Python 3 with json module not found"}'
    exit 1
fi

# ------------------------------------------------------------------
# Subcommand: tcp_ping
# ------------------------------------------------------------------
tcp_ping() {
    local address="$1" port="$2" timeout="$3" tag="$4"
    "$PYTHON" -c "
import socket, sys, time
addr = sys.argv[1]
port = int(sys.argv[2])
timeout = float(sys.argv[3])
start = time.time()
try:
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(timeout)
    s.connect((addr, port))
    elapsed = int((time.time() - start) * 1000)
    s.close()
    import json
    print(json.dumps({'success': True, 'latency_ms': elapsed}))
except Exception as e:
    import json
    print(json.dumps({'success': False, 'error': str(e)}))
" "$address" "$port" "$timeout"
}

# ------------------------------------------------------------------
# Subcommand: url_test
# ------------------------------------------------------------------
url_test() {
    # Read stdin JSON
    local input
    input=$(cat)
    "$PYTHON" -c "
import json, os, subprocess, sys, time, signal

data = json.loads(sys.stdin.buffer.read().decode() if hasattr(sys.stdin.buffer, 'read') else sys.stdin.read())

config_path  = data['config_path']
bin_type     = data['bin_type']
bin_path     = data['bin_path']
local_port   = data['local_port']
test_url     = data['test_url']
curl_timeout = data['curl_timeout']
tag          = data['tag']

# Resolve relative bin_path
script_dir = os.path.dirname(os.path.abspath('$0'))
if not os.path.isabs(bin_path):
    bin_path = os.path.normpath(os.path.join(script_dir, '..', bin_path))

config_filename = os.path.basename(config_path)
pid_file = config_path + '.pid'

# Check binary exists
if not os.path.isfile(bin_path):
    os.chmod(bin_path, 0o755) if os.path.exists(bin_path) else None
if not os.path.isfile(bin_path):
    print(json.dumps({'success': False, 'error': f'Binary not found: {bin_path}'}))
    sys.exit(0)

# Build command
bin_dir = os.path.dirname(os.path.abspath(bin_path))
env = os.environ.copy()
env['PATH'] = bin_dir + ':' + env.get('PATH', '')

if bin_type == 'xray':
    cmd = [bin_path, 'run', '-config', config_path]
elif bin_type == 'sslocal':
    cmd = [bin_path, '-c', config_path]
elif bin_type == 'sing-box':
    cmd = [bin_path, 'run', '-c', config_path]
else:
    print(json.dumps({'success': False, 'error': f'Unknown bin_type: {bin_type}'}))
    sys.exit(0)

# Start process in new session
try:
    proc = subprocess.Popen(
        cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        env=env, preexec_fn=os.setsid
    )
    with open(pid_file, 'w') as f:
        f.write(str(proc.pid))
except Exception as e:
    print(json.dumps({'success': False, 'error': f'Failed to start: {e}'}))
    sys.exit(0)

# Wait for port
port_ready = False
for _ in range(30):  # 15s max
    time.sleep(0.5)
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(1)
        s.connect(('127.0.0.1', local_port))
        s.close()
        port_ready = True
        break
    except Exception:
        pass

if not port_ready:
    cleanup(proc, pid_file, config_path, tag, config_filename)
    print(json.dumps({'success': False, 'error': 'Port did not become ready'}))
    sys.exit(0)

# Curl through SOCKS5
start = time.time()
try:
    curl_cmd = [
        'curl', '--socks5-hostname', f'127.0.0.1:{local_port}',
        '--connect-timeout', '3', '--max-time', str(curl_timeout),
        '-s', '-o', '/dev/null', '-w', '%{http_code}', test_url
    ]
    result = subprocess.run(curl_cmd, capture_output=True, text=True, timeout=curl_timeout + 5)
    http_code_str = result.stdout.strip()
    try:
        http_code = int(http_code_str)
    except ValueError:
        http_code = 0
    elapsed = int((time.time() - start) * 1000)

    valid_codes = {200, 204, 301, 302, 307, 308}
    if http_code in valid_codes:
        print(json.dumps({'success': True, 'latency_ms': elapsed, 'http_code': http_code}))
    else:
        print(json.dumps({'success': False, 'error': f'HTTP {http_code}', 'http_code': http_code, 'latency_ms': elapsed}))
except Exception as e:
    elapsed = int((time.time() - start) * 1000)
    print(json.dumps({'success': False, 'error': str(e), 'latency_ms': elapsed}))

# Cleanup
cleanup(proc, pid_file, config_path, tag, config_filename)
" <<< "$input"
}

# ------------------------------------------------------------------
# Cleanup helper — embedded in Python for url_test
# Three-layer orphan cleanup (§16.2 step 10)
# ------------------------------------------------------------------
# (The cleanup function is called from within the Python code above;
#  it's defined inline there but also available as a shell function
#  for manual cleanup if needed.)
cleanup_shell() {
    local pid_file="$1" config="$2" tag="$3" config_filename="$4"
    if [ -f "$pid_file" ]; then
        local pid
        pid=$(cat "$pid_file" 2>/dev/null || true)
        if [ -n "$pid" ]; then
            # Layer 1: PGID kill
            local pgid
            pgid=$(ps -o pgid= "$pid" 2>/dev/null | tr -d ' ') || true
            if [ -n "$pgid" ]; then
                kill -TERM -"$pgid" 2>/dev/null || true
                sleep 1
                kill -KILL -"$pgid" 2>/dev/null || true
            fi
        fi
        rm -f "$pid_file"
    fi
    # Layer 2: tag-based cleanup
    pgrep -af "$tag" 2>/dev/null | grep -v test.sh | while read -r p _; do
        kill -KILL "$p" 2>/dev/null || true
    done
    # Layer 3: config-filename-based cleanup
    pgrep -af "$config_filename" 2>/dev/null | grep -v test.sh | while read -r p _; do
        kill -KILL "$p" 2>/dev/null || true
    done
    rm -f "$config"
}

# ------------------------------------------------------------------
# Dispatch
# ------------------------------------------------------------------
case "${1:-}" in
    tcp_ping)
        tcp_ping "$2" "$3" "$4" "$5"
        ;;
    url_test)
        url_test
        ;;
    cleanup)
        cleanup_shell "$2" "$3" "$4" "$5"
        ;;
    *)
        echo '{"success": false, "error": "Unknown subcommand. Use tcp_ping or url_test"}'
        exit 1
        ;;
esac
