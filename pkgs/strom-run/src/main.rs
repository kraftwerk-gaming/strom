// strom-run: the outermost process of a strom game launch (`bin/<game>`).
//
// It replaces the host-side bash that used to hand-roll the game's
// process-tree lifecycle in lib/bwrap.nix (a flock, a cross-namespace
// shutdown FIFO reader, a /proc PPid orphan watchdog, composed signal
// traps and a wait loop). Those leaked the lock and the per-launch
// gamescope dirs whenever teardown took the SIGKILL path (sway
// window-close), because bash cannot atomically own a process tree.
//
// strom-run owns the tree via cgroup v2: it forks `bwrap ...` into a
// child cgroup and, on any teardown trigger, writes cgroup.kill. That
// SIGKILLs the whole subtree atomically from outside the pid namespace
// — bypassing both the "kill of pid 1 in an unshare-pid ns is dropped"
// kernel safeguard and the gamescope->reaper->winedevice waitpid()
// deadlock — and the inherited flock (fd 9) is released because
// strom-run is always reaped. The read-write game overlay is mounted
// with fuse-overlayfs INSIDE the bwrap namespace, so killing the tree
// tears down its mount-ns and the daemon + mount vanish with it; there
// is nothing host-side for strom-run to unmount.
//
// Teardown triggers, multiplexed in one poll() loop:
//   * the bwrap child exits           (pidfd)      -> normal game quit
//   * SIGINT / SIGTERM / SIGHUP       (signalfd)   -> Ctrl+C, or a terminal
//                                                     hangup (tmux kill /
//                                                     closed terminal): the
//                                                     kernel SIGHUPs the
//                                                     foreground process
//                                                     group, which is us
//   * a write to the shutdown FIFO    (fifo)       -> sway window-close
//                                                     (proton.nix writes it)
//
// The game tree is put in its OWN process group (setpgid in the child), so
// terminal signals hit strom-run rather than the game directly, and
// strom-run alone decides teardown. There is deliberately NO parent-death
// (orphan) trigger: a pidfd on the parent false-fires on nix-run's
// transient launcher parent exiting mid-startup (it reparents us to pid 1),
// which tore games down ~50% of launches. Terminal hangup is already
// covered by the SIGHUP path above; the only case dropped is "the launcher
// process is killed but the terminal lives", which is rare and acceptable.
//
// v1 requires a writable/delegated cgroup v2 (any systemd-logind or
// elogind seat). If none is available it errors out before launching.
// The PR_SET_CHILD_SUBREAPER fallback and the static-musl Android build
// are deferred follow-ups.

use std::ffi::CString;
use std::fs;
use std::mem;
use std::os::raw::c_int;
use std::path::PathBuf;
use std::process::exit;
use std::ptr;
use std::thread::sleep;
use std::time::{Duration, Instant};

// stderr can be a pipe to an already-dead tee/pager (a tmux pane kill
// takes the pipeline down first); elog! panics on EPIPE and would
// abort teardown before it reaps the gs dirs. Log best-effort instead.
macro_rules! elog {
    ($($arg:tt)*) => {{
        use std::io::Write;
        let _ = writeln!(std::io::stderr(), $($arg)*);
    }};
}

fn die(msg: &str) -> ! {
    elog!("strom-run: {msg}");
    exit(1);
}

struct Config {
    cgroup_name: String,
    control_dir: Option<String>,
    control_fifo: Option<String>,
    gs_dirs: Option<String>,
    childv: Vec<String>,
}

fn parse() -> Config {
    let mut args = std::env::args().skip(1);
    let mut c = Config {
        cgroup_name: String::new(),
        control_dir: None,
        control_fifo: None,
        gs_dirs: None,
        childv: Vec::new(),
    };
    macro_rules! val {
        ($o:expr) => {
            args.next()
                .unwrap_or_else(|| die(&format!("{} needs a value", $o)))
        };
    }
    while let Some(a) = args.next() {
        match a.as_str() {
            "--cgroup-name" => c.cgroup_name = val!("--cgroup-name"),
            "--control-dir" => c.control_dir = Some(val!("--control-dir")),
            "--control-fifo" => c.control_fifo = Some(val!("--control-fifo")),
            "--gs-dirs" => c.gs_dirs = Some(val!("--gs-dirs")),
            "--" => {
                c.childv = args.by_ref().collect();
                break;
            }
            other => die(&format!("unknown argument: {other}")),
        }
    }
    if c.cgroup_name.is_empty() {
        die("--cgroup-name is required");
    }
    if c.childv.is_empty() {
        die("no command given after --");
    }
    c
}

// ---- cgroup v2 ------------------------------------------------------------

struct Cgroup {
    dir: PathBuf,
}

impl Cgroup {
    // Create a child cgroup under our own (delegated) cgroup and return
    // it. The child holds only the game tree; strom-run stays in the
    // parent so cgroup.kill never targets itself.
    fn create(name: &str) -> std::io::Result<Cgroup> {
        let self_cg = fs::read_to_string("/proc/self/cgroup")?;
        let rel = self_cg
            .lines()
            .find_map(|l| l.strip_prefix("0::"))
            .ok_or_else(|| std::io::Error::other("no cgroup v2 line in /proc/self/cgroup"))?
            .trim();
        let parent = PathBuf::from("/sys/fs/cgroup").join(rel.trim_start_matches('/'));
        let dir = parent.join(format!("{name}.{}", std::process::id()));
        // A stale dir from a crashed run with a reused pid is unlikely;
        // tolerate it by reusing.
        match fs::create_dir(&dir) {
            Ok(()) => {}
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => {}
            Err(e) => return Err(e),
        }
        Ok(Cgroup { dir })
    }

    fn add_pid(&self, pid: c_int) -> std::io::Result<()> {
        fs::write(self.dir.join("cgroup.procs"), pid.to_string())
    }

    fn kill(&self) {
        let _ = fs::write(self.dir.join("cgroup.kill"), "1");
    }

    // Block until the cgroup reports no member processes, bounded.
    fn wait_empty(&self, timeout: Duration) {
        let start = Instant::now();
        loop {
            match fs::read_to_string(self.dir.join("cgroup.events")) {
                Ok(s) => {
                    if s.lines().any(|l| l.trim() == "populated 0") {
                        return;
                    }
                }
                Err(_) => return, // cgroup already gone
            }
            if start.elapsed() > timeout {
                elog!("strom-run: cgroup still populated after {timeout:?}; proceeding");
                return;
            }
            sleep(Duration::from_millis(5));
        }
    }

    fn remove(&self) {
        for _ in 0..200 {
            if fs::remove_dir(&self.dir).is_ok() || !self.dir.exists() {
                return;
            }
            sleep(Duration::from_millis(5));
        }
    }
}

// ---- syscall helpers ------------------------------------------------------

fn pidfd_open(pid: c_int) -> Option<c_int> {
    let r = unsafe { libc::syscall(libc::SYS_pidfd_open, pid, 0) };
    if r < 0 {
        None
    } else {
        Some(r as c_int)
    }
}

fn open_fifo(path: &str) -> c_int {
    let c = match CString::new(path) {
        Ok(c) => c,
        Err(_) => return -1,
    };
    // O_RDWR so open never blocks waiting for a writer; O_NONBLOCK so
    // poll drives the reads.
    unsafe {
        libc::open(
            c.as_ptr(),
            libc::O_RDWR | libc::O_NONBLOCK | libc::O_CLOEXEC,
        )
    }
}

fn pollin(fd: c_int) -> libc::pollfd {
    libc::pollfd {
        fd,
        events: libc::POLLIN,
        revents: 0,
    }
}

// ---- supervision loop -----------------------------------------------------

enum Reason {
    ChildExit,
    Signal(c_int),
    Fifo,
}

fn drain(fd: c_int) {
    let mut buf = [0u8; 256];
    while unsafe { libc::read(fd, buf.as_mut_ptr() as *mut _, buf.len()) } > 0 {}
}

fn read_term_signal(sfd: c_int) -> Option<c_int> {
    let sz = mem::size_of::<libc::signalfd_siginfo>();
    let mut buf = vec![0u8; sz];
    let mut found = None;
    loop {
        let r = unsafe { libc::read(sfd, buf.as_mut_ptr() as *mut _, sz) };
        if r != sz as isize {
            break;
        }
        let si: libc::signalfd_siginfo = unsafe { ptr::read(buf.as_ptr() as *const _) };
        let signo = si.ssi_signo as c_int;
        if signo == libc::SIGINT || signo == libc::SIGTERM || signo == libc::SIGHUP {
            found = Some(signo); // last one wins; any is enough to tear down
        }
        // SIGCHLD is drained and ignored: the bwrap child's exit is the
        // authoritative event via its pidfd.
    }
    found
}

fn supervise(sfd: c_int, child_pidfd: c_int, fifo_fd: c_int) -> Reason {
    loop {
        let mut pfds: Vec<libc::pollfd> = Vec::with_capacity(3);
        pfds.push(pollin(sfd)); // 0
        pfds.push(pollin(child_pidfd)); // 1
        let fifo_idx = if fifo_fd >= 0 {
            pfds.push(pollin(fifo_fd));
            Some(pfds.len() - 1)
        } else {
            None
        };

        let n = unsafe { libc::poll(pfds.as_mut_ptr(), pfds.len() as libc::nfds_t, -1) };
        if n < 0 {
            continue; // EINTR; signals are blocked so this is rare
        }

        // Child exit dominates: the tree is already gone.
        if pfds[1].revents != 0 {
            return Reason::ChildExit;
        }
        if let Some(i) = fifo_idx {
            if pfds[i].revents != 0 {
                drain(fifo_fd);
                return Reason::Fifo;
            }
        }
        if pfds[0].revents != 0 {
            if let Some(sig) = read_term_signal(sfd) {
                return Reason::Signal(sig);
            }
        }
    }
}

// ---- teardown -------------------------------------------------------------

fn reap_gs_dirs(file: &str) {
    if let Ok(content) = fs::read_to_string(file) {
        for line in content.lines() {
            let p = line.trim();
            if p.contains("/strom-gs-") {
                let _ = fs::remove_dir_all(p);
            }
        }
    }
}

fn teardown(cfg: &Config, cg: &Cgroup, child: c_int, reason: Reason) -> i32 {
    let why = match reason {
        Reason::ChildExit => "child-exit",
        Reason::Signal(s) => {
            return teardown_logged(cfg, cg, child, reason, &format!("signal {s}"))
        }
        Reason::Fifo => "shutdown-fifo",
    };
    teardown_logged(cfg, cg, child, reason, why)
}

fn teardown_logged(cfg: &Config, cg: &Cgroup, child: c_int, reason: Reason, why: &str) -> i32 {
    elog!("strom-run: tearing down ({why})");
    // 1. Atomic, membership-based SIGKILL of the whole tree. On a normal
    //    quit (ChildExit) the cgroup is already empty and this is a
    //    no-op; otherwise it reaps gamescope/proton/wine from outside the
    //    pid namespace. The direct kill is a belt-and-suspenders fallback
    //    if the child somehow never joined the cgroup.
    cg.kill();
    unsafe {
        libc::kill(child, libc::SIGKILL);
    }

    // 2. Reap the bwrap child and capture its real status (for ChildExit).
    let mut status: c_int = 0;
    unsafe {
        libc::waitpid(child, &mut status, 0);
    }
    if let Reason::ChildExit = reason {
        if libc::WIFEXITED(status) {
            elog!("strom-run: bwrap exited code {}", libc::WEXITSTATUS(status));
        } else if libc::WIFSIGNALED(status) {
            elog!(
                "strom-run: bwrap killed by signal {}",
                libc::WTERMSIG(status)
            );
        }
    }

    // 3. Wait for the subtree to drain, then remove the cgroup. The game
    //    overlay was mounted with fuse-overlayfs INSIDE the bwrap
    //    namespace, so killing the tree tears its mount-ns down and the
    //    daemon + mount vanish with it -- there is nothing host-side to
    //    unmount or reap.
    cg.wait_empty(Duration::from_secs(10));
    cg.remove();

    // 4. Reap the per-launch gamescope private dirs the inner wrapper
    //    recorded but couldn't clean (SIGKILL skipped its EXIT trap).
    if let Some(f) = &cfg.gs_dirs {
        reap_gs_dirs(f);
    }

    // 5. Remove the host control dir (shutdown FIFO + gs-dirs list).
    if let Some(d) = &cfg.control_dir {
        let _ = fs::remove_dir_all(d);
    }

    // 6. Exit. Any inherited flock (fd 9) is released as we exit.
    match reason {
        Reason::ChildExit => {
            if libc::WIFEXITED(status) {
                libc::WEXITSTATUS(status)
            } else if libc::WIFSIGNALED(status) {
                128 + libc::WTERMSIG(status)
            } else {
                0
            }
        }
        Reason::Signal(s) => 128 + s,
        Reason::Fifo => 0,
    }
}

// ---- main -----------------------------------------------------------------

fn main() {
    let cfg = parse();

    // Block the signals we handle so they arrive only via signalfd and
    // are inherited-blocked by the child until it resets the mask.
    let mut mask: libc::sigset_t = unsafe { mem::zeroed() };
    unsafe {
        libc::sigemptyset(&mut mask);
        for s in [libc::SIGINT, libc::SIGTERM, libc::SIGHUP, libc::SIGCHLD] {
            libc::sigaddset(&mut mask, s);
        }
        if libc::sigprocmask(libc::SIG_BLOCK, &mask, ptr::null_mut()) != 0 {
            die("sigprocmask failed");
        }
    }
    let sfd = unsafe { libc::signalfd(-1, &mask, libc::SFD_NONBLOCK | libc::SFD_CLOEXEC) };
    if sfd < 0 {
        die("signalfd failed");
    }

    let cg = Cgroup::create(&cfg.cgroup_name).unwrap_or_else(|e| {
        die(&format!(
            "could not create cgroup ({e}); strom-run v1 needs a delegated cgroup v2 \
             (a systemd-logind or elogind seat). Launch from such a session, or run the \
             game directly."
        ))
    });

    // Sync pipe: the child blocks until the parent has moved it into the
    // cgroup, so every process bwrap forks is born inside it.
    let mut sync = [0 as c_int; 2];
    if unsafe { libc::pipe(sync.as_mut_ptr()) } != 0 {
        die("pipe failed");
    }
    let (sync_r, sync_w) = (sync[0], sync[1]);

    let pid = unsafe { libc::fork() };
    if pid < 0 {
        die("fork failed");
    }

    if pid == 0 {
        // ---- child: become a cgroup-confined, own-pgroup bwrap ----
        unsafe {
            libc::close(sync_w);
            // Own process group so terminal signals (Ctrl+C) reach only
            // strom-run, which then orchestrates teardown.
            libc::setpgid(0, 0);
            // Wait until the parent confirms we're in the cgroup.
            let mut b = [0u8; 1];
            let _ = libc::read(sync_r, b.as_mut_ptr() as *mut _, 1);
            libc::close(sync_r);
            // Drop every inherited fd >= 3 (the flock fd, signalfd, ...)
            // so the game gets clean stdio and only strom-run holds the
            // lock. fd numbers are low; 3..256 covers them.
            for fd in 3..256 {
                libc::close(fd);
            }
            // Reset the signal mask for the game.
            let mut empty: libc::sigset_t = mem::zeroed();
            libc::sigemptyset(&mut empty);
            libc::sigprocmask(libc::SIG_SETMASK, &empty, ptr::null_mut());

            let path = CString::new(cfg.childv[0].as_str()).unwrap();
            let cargs: Vec<CString> = cfg
                .childv
                .iter()
                .map(|s| CString::new(s.as_str()).unwrap())
                .collect();
            let mut argv: Vec<*const libc::c_char> = cargs.iter().map(|c| c.as_ptr()).collect();
            argv.push(ptr::null());
            // execvp so the command (e.g. "bwrap") resolves via the PATH
            // the wrapper exported; an absolute path also works.
            libc::execvp(path.as_ptr(), argv.as_ptr());
            // Only reached if exec failed.
            libc::_exit(127);
        }
    }

    // ---- parent: supervise ----
    unsafe {
        libc::close(sync_r);
    }
    if let Err(e) = cg.add_pid(pid) {
        unsafe {
            libc::kill(pid, libc::SIGKILL);
        }
        cg.remove();
        die(&format!("could not move child into cgroup: {e}"));
    }
    unsafe {
        let _ = libc::write(sync_w, [1u8].as_ptr() as *const _, 1);
        libc::close(sync_w);
    }

    let child_pidfd = pidfd_open(pid).unwrap_or_else(|| die("pidfd_open(child) failed"));
    let fifo_fd = cfg.control_fifo.as_deref().map(open_fifo).unwrap_or(-1);

    let reason = supervise(sfd, child_pidfd, fifo_fd);
    let code = teardown(&cfg, &cg, pid, reason);
    exit(code);
}
