if vim.g.loaded_termyank then
  return
end
vim.g.loaded_termyank = true

require("termyank").setup()
