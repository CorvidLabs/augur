# Demo

The animated demo in the README and on the site is generated from these two files,
so anyone can reproduce it from scratch:

- `setup.sh` builds a throwaway git repo (`/tmp/demo-augur` by default) with a short
  history and an uncommitted edit to a sensitive file, so `augur check` returns REVIEW.
- `demo.tape` is a [VHS](https://github.com/charmbracelet/vhs) script that records the
  run as a GIF. It passes `--color always` because VHS capture is not always detected
  as an interactive TTY, and `augur check --color auto` intentionally stays plain when
  stdout is not a terminal.

## Regenerate

```sh
brew install corvidlabs/tap/augur charmbracelet/tap/vhs
./demo/setup.sh
vhs demo/demo.tape
mv demo.gif site/public/demo.gif
```

The GIF is served from `site/public/demo.gif` (the site and the README both point at it).
