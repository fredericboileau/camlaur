# aur-chroot - build packages with systemd-nspawn (Nim port sketch)
# Untested sketch: Nim was not available to compile it.
import std/[os, osproc, parseopt, strutils, strformat, sequtils]
import shell

const argv0 = "chroot"
const etcdir = "/etc/aurutils"
const shrdir = "/usr/share/devtools"

let machine = execProcess("uname", args = ["-m"], options = {poUsePath}).strip

# --- options ---------------------------------------------------------------
var
  directory = "/var/lib/aurbuild" / machine
  makechrootpkgArgs = @["-cu"]
  makepkgArgs: seq[string]
  bindRo, bindRw, packages: seq[string]
  pacmanConf, makepkgConf, suffix = ""
  update, build, create, status, printPath = false

proc usage() =
  stderr.writeLine &"usage: {argv0} [-BU] [--create] [-CDM path] [package...]"
  quit 1

# Flags listed here take no value; every other option consumes the next arg.
var p = initOptParser(
  shortNoVal = {'A', 'B', 'N', 'T', 'U'},
  longNoVal = @["build", "update", "create", "status", "path", "ignorearch",
                "nocheck", "namcap", "checkpkg", "temp"])

proc apply(key, val: string) =
  case key
  of "x", "suffix": suffix = val
  of "B", "build": build = true
  of "U", "update": update = true
  of "create": create = true
  of "status": status = true
  of "path": printPath = true
  of "A", "ignorearch": makepkgArgs.add "--ignorearch"
  of "nocheck": makepkgArgs.add "--nocheck"
  of "makepkg-args", "margs": makepkgArgs.add val.split(',')
  of "C", "pacman-conf": pacmanConf = val
  of "D", "directory": directory = val
  of "M", "makepkg-conf": makepkgConf = val
  of "bind": bindRo.add val
  of "bind-rw": bindRw.add val
  of "N", "namcap": makechrootpkgArgs.add "-n"
  of "checkpkg": makechrootpkgArgs.add "-C"
  of "T", "temp": makechrootpkgArgs.add "-T"
  of "user": makechrootpkgArgs.add ["-U", val]
  of "makechrootpkg-args", "cargs": makechrootpkgArgs.add val.split(',')
  else: usage()

# parseopt reads `--long value` from the next arg, but not `-C value`:
# remember short options that still need their value.
const shortWithVal = ["x", "C", "D", "M"]
var pending = ""

while true:
  p.next()
  if p.kind == cmdEnd: break
  if pending != "":
    if p.kind != cmdArgument: usage()
    apply(pending, p.key)
    pending = ""
  elif p.kind == cmdArgument:
    packages.add p.key
  elif p.kind == cmdLongOption and p.key == "":
    # bare `--`: parseopt hands the next arg over as its value
    if p.val != "": packages.add p.val
    packages.add p.remainingArgs
    break
  elif p.kind == cmdShortOption and p.key in shortWithVal and p.val == "":
    pending = p.key
  else:
    apply(p.key, p.val)
if pending != "": usage()

# --- locate pacman.conf / makepkg.conf --------------------------------------
let (pacmanPaths, makepkgPaths) =
  if suffix != "":
    (@[etcdir / &"pacman-{suffix}.conf", etcdir / &"pacman-{machine}.conf",
       shrdir / &"pacman.conf.d/{suffix}.conf",
       shrdir / &"pacman.conf.d/aurutils-{machine}.conf"],
     @[etcdir / &"makepkg-{suffix}.conf", etcdir / &"makepkg-{machine}.conf",
       shrdir / &"makepkg.conf.d/{suffix}.conf",
       shrdir / &"makepkg.conf.d/{machine}.conf"])
  else:
    (@[etcdir / &"pacman-{machine}.conf",
       shrdir / &"pacman.conf.d/aurutils-{machine}.conf"],
     @[etcdir / &"makepkg-{machine}.conf",
       shrdir / &"makepkg.conf.d/{machine}.conf"])

proc firstExisting(paths: seq[string]): string =
  for p in paths:
    if fileExists(p): return p

proc diag(what: string, checked: seq[string]) =
  stderr.writeLine &"""Error:
    aur-{argv0} could not find a {what}(5) file for container usage. Before
    using aur-{argv0}, make sure this file is created and valid. See OPTIONS in
    aur-{argv0}(1) for configuration details.

    The following file paths were checked:"""
  for c in checked: stderr.writeLine "        ", quoteShell(c)
  quit 2

if pacmanConf == "": pacmanConf = firstExisting(pacmanPaths)
if makepkgConf == "": makepkgConf = firstExisting(makepkgPaths)

if pacmanConf == "": diag("pacman.conf", pacmanPaths)
elif not fileExists(pacmanConf): diag("pacman.conf", @[pacmanConf])
elif makepkgConf == "": diag("makepkg.conf", makepkgPaths)
elif not fileExists(makepkgConf): diag("makepkg.conf", @[makepkgConf])

if status or not (update or build or create or printPath):
  echo &"chroot:{directory}\npacman:{pacmanConf}\nmakepkg:{makepkgConf}"
  quit 0

# --- elevation command (may contain spaces, e.g. "sudo -A") -----------------
let auth = getEnv("AUR_PACMAN_AUTH", "sudo")
let authArgs =
  if auth == "sudo":
    "--preserve-env=SRCDEST,SRCPKGDEST,PKGDEST,LOGDEST,MAKEFLAGS,PACKAGER,GNUPGHOME,SSH_AUTH_SOCK"
  else: ""

# Run one command line through the shell macro; stop like `set -o errexit`.
template sh(code: untyped) =
  let (_, rc) = shellVerbose:
    code
  if rc != 0: quit rc

# Arrays must be pre-quoted into one string before splicing with ($x):
# the shell macro builds a /bin/sh command line, it does not take a seq.
proc q(args: seq[string]): string = quoteShellCommand(args)

# --- bind-mount file:// repositories (#461) --------------------------------
for line in execProcess("pacman-conf", args = ["--config", pacmanConf],
                        options = {poUsePath}).splitLines:
  let parts = line.split(" = ", maxsplit = 1)
  if parts.len == 2 and parts[0] == "Server" and parts[1].startsWith("file://"):
    bindRw.add parts[1]["file://".len .. ^1]

let root = directory / "root"

# --- create --------------------------------------------------------------
if create:
  let basePackages =
    if packages.len > 0: packages
    elif machine == "x86_64" and
         execProcess("pacini", args = ["--section=multilib", pacmanConf],
                     options = {poUsePath}).strip != "":
      @["base-devel", "multilib-devel"]
    else: @["base-devel"]

  if not dirExists(directory):
    sh:
      ($auth) install -d ($directory) -m 755 -v
  if not dirExists(root):
    let pkgs = q(basePackages)
    sh:
      ($auth) mkarchroot -C ($pacmanConf) -M ($makepkgConf) ($root) ($pkgs)

if not dirExists(root):
  stderr.writeLine &"{argv0}: {quoteShell(root)} is not a directory"
  stderr.writeLine &"{argv0}: did you run aur chroot --create?"
  quit 20

# --- update --------------------------------------------------------------
if update:
  let binds = q(bindRo.mapIt("--bind-ro=" & it) & bindRw.mapIt("--bind=" & it))
  let pkgs = q(packages)
  sh:
    ($auth) arch-nspawn -C ($pacmanConf) -M ($makepkgConf) ($root) ($binds) pacman -Syu "--noconfirm" ($pkgs)

if printPath:
  echo expandFilename(root)
  quit 0

# --- build ---------------------------------------------------------------
if build:
  let binds = q(bindRo.mapIt("-D" & it) & bindRw.mapIt("-d" & it))
  let cargs = q(makechrootpkgArgs)
  let margs = q(makepkgArgs)
  sh:
    ($auth) ($authArgs) makechrootpkg -r ($directory) ($binds) ($cargs) "--" ($margs)
