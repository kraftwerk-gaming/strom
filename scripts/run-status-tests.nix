{
  pkgs,
  statusPage,
}:

let
  python = pkgs.python3.withPackages (ps: [
    ps.pytest
    ps.playwright
    ps.pytest-playwright
  ]);
in
pkgs.writeShellScriptBin "run-status-tests" ''
  set -euo pipefail
  export PLAYWRIGHT_BROWSERS_PATH=${pkgs.playwright-driver.browsers}
  export STATUS_PAGE_DIR=${statusPage}
  exec ${python.interpreter} -m pytest \
    ${../tests/test_status_page.py} \
    -v \
    "$@"
''
