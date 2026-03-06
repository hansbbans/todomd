# Dotfiles Setup Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a private GitHub repo (`hansbbans/dotfiles`) to version-control Claude config files, with symlinks so the live `~/.claude/` directory always reads from the repo.

**Architecture:** `~/dotfiles/` is the git repo. Files live there; symlinks in `~/.claude/` point into the repo. Adding/editing a skill or config is instantly live and one `git push` away from being synced.

**Tech Stack:** bash, git, GitHub CLI (`gh`)

---

### Task 1: Create dotfiles directory structure

**Files:**
- Create: `~/dotfiles/claude/skills/` (directory)
- Create: `~/dotfiles/install.sh`
- Create: `~/dotfiles/.gitignore`
- Create: `~/dotfiles/README.md`

**Step 1: Create directories**

```bash
mkdir -p ~/dotfiles/claude/skills
```

**Step 2: Verify structure**

```bash
ls ~/dotfiles/claude/
# Expected: skills/
```

**Step 3: Create install.sh**

```bash
cat > ~/dotfiles/install.sh << 'EOF'
#!/bin/bash
set -e

DOTFILES="$(cd "$(dirname "$0")" && pwd)"

echo "Installing dotfiles from $DOTFILES..."

# Back up existing ~/.claude/skills if it's a real directory (not a symlink)
if [ -d ~/.claude/skills ] && [ ! -L ~/.claude/skills ]; then
  echo "Backing up existing ~/.claude/skills to ~/.claude/skills.bak"
  mv ~/.claude/skills ~/.claude/skills.bak
fi

# Create symlink
ln -sf "$DOTFILES/claude/skills" ~/.claude/skills
echo "Linked ~/.claude/skills -> $DOTFILES/claude/skills"

echo "Done."
EOF
chmod +x ~/dotfiles/install.sh
```

**Step 4: Create .gitignore**

```bash
cat > ~/dotfiles/.gitignore << 'EOF'
.DS_Store
*.local
EOF
```

**Step 5: Create README.md**

```bash
cat > ~/dotfiles/README.md << 'EOF'
# dotfiles

Personal config files for Claude Code and other tools.

## Setup on a new machine

```bash
git clone git@github.com:hansbbans/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```
EOF
```

**Step 6: Verify all files exist**

```bash
ls ~/dotfiles/
# Expected: README.md  claude/  install.sh  .gitignore
```

---

### Task 2: Move existing skill into dotfiles

**Files:**
- Move: `~/.claude/skills/spec` → `~/dotfiles/claude/skills/spec`

**Step 1: Move the spec skill**

```bash
mv ~/.claude/skills/spec ~/dotfiles/claude/skills/spec
```

**Step 2: Verify it moved**

```bash
ls ~/dotfiles/claude/skills/
# Expected: spec/
```

---

### Task 3: Copy Claude settings into dotfiles

**Files:**
- Copy: `~/.claude/settings.json` → `~/dotfiles/claude/settings.json`

**Step 1: Copy settings**

```bash
cp ~/.claude/settings.json ~/dotfiles/claude/settings.json
```

**Step 2: Verify**

```bash
ls ~/dotfiles/claude/
# Expected: settings.json  skills/
```

---

### Task 4: Initialize git repo and push to GitHub

**Step 1: Initialize git**

```bash
cd ~/dotfiles
git init
git add .
git commit -m "init: claude dotfiles with skills and settings"
```

**Step 2: Create private GitHub repo**

```bash
gh repo create hansbbans/dotfiles --private --source=. --remote=origin --push
```

**Step 3: Verify it pushed**

```bash
gh repo view hansbbans/dotfiles
# Expected: shows repo details
```

---

### Task 5: Create symlink and verify everything works

**Step 1: Remove the now-empty skills directory**

```bash
rmdir ~/.claude/skills
```

**Step 2: Run install script to create symlink**

```bash
cd ~/dotfiles && ./install.sh
```

**Step 3: Verify symlink**

```bash
ls -la ~/.claude/skills
# Expected: ~/.claude/skills -> /Users/hans/dotfiles/claude/skills
```

**Step 4: Verify skill is still accessible**

```bash
ls ~/.claude/skills/
# Expected: spec/
```

**Step 5: Commit install.sh confirmation**

No code change needed — already committed in Task 4.

---

## Future workflow (for reference)

**Add a new skill:**
```bash
# Drop file in ~/dotfiles/claude/skills/
# It's instantly live in Claude Code
cd ~/dotfiles && git add . && git commit -m "feat: add new-skill" && git push
```

**Sync to another machine:**
```bash
git clone git@github.com:hansbbans/dotfiles.git ~/dotfiles
cd ~/dotfiles && ./install.sh
```

**Pull updates on existing machine:**
```bash
cd ~/dotfiles && git pull
```
