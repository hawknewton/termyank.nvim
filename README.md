# termyank.nvim

Clean up register contents after yanking, deleting, or changing text inside a
Neovim `:terminal` buffer: strip `\r` characters, and collapse wrap-induced
line breaks so word-level yanks that cross terminal row boundaries paste as a
single string.

## Why

Terminal output uses `\r\n` line endings and terminal rows hard-wrap long
lines. That means a URL, filename, or shell command can look like one logical
token on screen but land in your register as multiple `^M`-terminated lines.
Pasting splits the token across lines. This plugin silently normalizes those
yanks so they paste cleanly.

## Install

### lazy.nvim

```lua
{ "hawknewton/termyank.nvim" }
```

### packer.nvim

```lua
use "hawknewton/termyank.nvim"
```

No configuration required — the plugin auto-loads and starts working
immediately.

## How it works

- A `TextYankPost` autocmd handles yanks, deletes, and changes (Neovim fires
  this event for all three) originating in buffers where `&buftype == "terminal"`.
- A buffer-local `TextChanged` autocmd attached on `TermOpen` catches any other
  register writes inside terminal buffers as a safety net.

Behavior by selection type:

- **Charwise (`v`, `yw`, `yW`, `yi"`, `y$`, …) and Linewise (`V`, `yy`)**:
  every `\r` is stripped and all lines are joined into a single charwise line.
  A linewise yank from a terminal becomes charwise in the register — use a
  blockwise yank if you want multi-line paste behavior.
- **Blockwise (`<C-v>`)**: left completely untouched. Rectangular selections
  keep their structure and their `\r` characters.
