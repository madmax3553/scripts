# scripts

## Description

CLI scripts for journaling with a simple markdown wiki (~/journal), plus helpers for TODO review and git repo utilities.

## Setup

Requirements: bash, grep, sed, nvim (optional).

Setup:
- Create dirs and symlinks:
  mkdir -p ~/bin ~/journal/diary
  chmod +x wiki-daily-plan wiki-helper wiki-review-todos
  ln -sf "$(pwd)/wiki-daily-plan" ~/bin/wiki-daily-plan
  ln -sf "$(pwd)/wiki-helper" ~/bin/wiki-helper
  ln -sf "$(pwd)/wiki-review-todos" ~/bin/wiki-review-todos
- Ensure ~/bin on PATH (e.g., add to ~/.bashrc): export PATH="$HOME/bin:$PATH"

## Usage

Daily flow:
- Morning: run wiki-helper; it creates today's diary at ~/journal/diary/YYYY-MM-DD.md, shows outstanding TODOs, then choose 1 to edit in nvim and fill Plan/Morning/Afternoon/Evening/Reflections; add tasks as "- [ ]" and mark done as "- [X]" or "- [✓]".
- Any time: wiki-daily-plan -o opens today directly; keep your main list at ~/journal/TODO.md, optional notes in ~/journal/notes/.
- Review: run wiki-review-todos to list incomplete items from TODO.md, the last 7 days of diary, and notes; triage/migrate as needed.
Tips: adjust the 7‑day window by editing -mtime in wiki-review-todos; you can alias jj='wiki-helper' for convenience.

## Neovim Wiki Keybinds
Within vimwiki buffers:
- <leader>wT  Open main TODO list
- <leader>wr  Review TODOs (terminal)
- <leader>wp  Generate today's plan
- <leader>wh  Run combined helper (plan + review)
- <leader>wi  Diary index
- <leader>wd  Create diary note (today)
- <C-Space> / <leader>wx Toggle checkbox
- <leader>wL  Link current TODO line to main TODO.md

General dashboard and navigation:
- <leader>h  Open Snacks dashboard
- <leader>wi / <leader>wd for quick journal entry/index from anywhere

Checkbox states use symbols: space (open), ○, ◐, ●, ✓ (done).
