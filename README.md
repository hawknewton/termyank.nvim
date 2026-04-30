# termyank.nvim

For us poor bastards that don't just use tmux for some reason.

Clean up register contents after yanking, deleting, or changing text inside a Neovim `:terminal` buffer: strip `\r` characters, and collapse wrap-induced line breaks so word-level yanks that cross terminal row boundaries paste as a single string.

If you want to preserve `\r`'s use a **Blockwise** select (`<C-v>`).

## Why

Terminal output uses `\r\n` line endings and terminal rows hard-wrap long lines. That means a URL, filename, or shell command can look like one logical token on screen but land in your register as multiple `^M`-terminated lines. Pasting splits the token across lines. This plugin silently normalizes those yanks so they paste cleanly.

## Install

### lazy.nvim

```lua
{ "hawknewton/termyank.nvim" }
```

### packer.nvim

```lua
use "hawknewton/termyank.nvim"
```

## Configuration

All options are passed to `setup()`. Defaults shown below.

```lua
require("termyank").setup({
  -- When true, override the following text objects inside terminal buffers
  -- so they extend across adjacent non-blank buffer lines. Useful when a
  -- token/string/bracketed expression was visually wrapped across terminal
  -- rows by the PTY.
  --
  -- Overridden objects: iW aW, i" a", i' a', i` a`, i( a(, ib ab, i[ a[,
  -- i{ a{, iB aB (and the matching close-delimiter keys).
  text_objects_span_lines = true,
})
```

With lazy.nvim:

```lua
{
  "hawknewton/termyank.nvim",
  opts = { text_objects_span_lines = true },
}
```

## Commands

- `:TermYankOn` — enable register sanitization.
- `:TermYankOff` — disable sanitization (registers are left untouched after yanks in terminal buffers).
- `:TermYankToggle` — flip between on and off.

Sanitization is on by default. Text-object overrides are not affected by these commands — they stay installed once `text_objects_span_lines = true` at setup time.

## How it works

- A `TextYankPost` autocmd handles yanks, deletes, and changes (Neovim fires this event for all three) originating in buffers where `&buftype == "terminal"`.
- A buffer-local `TextChanged` autocmd attached on `TermOpen` catches any other register writes inside terminal buffers as a safety net.
- On `TermOpen` the plugin sets `wrap` for the window so navigating past the right edge in normal mode doesn't side-scroll into the terminal's trailing padding.
- On `TermOpen`, if `text_objects_span_lines = true`, buffer-local operator-pending and visual-mode mappings are installed for the wrap-aware text objects listed above.

Behavior by selection type:

- **Charwise (`v`, `yw`, `yW`, `yi"`, `y$`, …) and Linewise (`V`, `yy`)**: every `\r` is stripped and all lines are joined into a single charwise line. A linewise yank from a terminal becomes charwise in the register — use a blockwise yank if you want multi-line paste behavior.
- **Blockwise (`<C-v>`)**: left completely untouched. Rectangular selections keep their structure and their `\r` characters.

### Wrap-aware text objects

When `text_objects_span_lines = true`, the overridden text objects behave like their builtin counterparts but search across adjacent non-blank buffer lines. Blank lines act as boundaries (so a yank won't accidentally swallow the next paragraph of terminal output).

- `iW` / `aW` — extended WORD that spans wrapped rows.
- `i"` / `a"`, `i'` / `a'`, `` i` `` / `` a` `` — quoted strings that wrap.
- `i(` / `a(` (and `ib` / `ab`, `i)` / `a)`) — parens, with nesting.
- `i[` / `a[` (and `i]` / `a]`) — brackets, with nesting.
- `i{` / `a{` (and `iB` / `aB`, `i}` / `a}`) — braces, with nesting.

After the text object selects the multi-line range, the `TextYankPost` handler collapses it into a single charwise register entry as usual — so `yiW` on a wrapped URL yields the whole URL, and `yi"` on a wrapped quoted string yields the whole string, ready to paste as one line.
