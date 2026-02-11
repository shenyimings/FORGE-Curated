export default {
  "*.md": ["markdownlint-cli2", "cspell lint --quiet --no-must-find-files --files"],
  "*.{json,yml}": ["prettier --list-different"],
  "*.sol": ["prettier --list-different"],
};
