# Contributing to Callout

First off, thank you. This project exists because dispatch software shouldn't require a second mortgage, and every person who contributes makes that more true.

## The Short Version

1. Fork the repo
2. Create a branch (`git checkout -b my-thing`)
3. Make your changes
4. Run the tests (`make test`)
5. Open a pull request

## What We're Looking For

Genuinely, all sorts.

- **Bug fixes.** If something is wrong, fix it. You don't need permission.
- **Tests.** More tests are always welcome. The engine has a stress harness but the core modules could always use more coverage.
- **Documentation.** If something confused you, it'll confuse someone else. Write the explanation you wish you'd had.
- **Features.** Check the issues first to see what's planned. If you've got an idea that isn't listed, open an issue and let's talk about it before you write 500 lines.

## What This Project Cares About

**Correctness over cleverness.** This is dispatch software. It tells emergency responders where to go. A bug here isn't an inconvenience, it's a safety problem. Write boring, obvious code. If your PR is slightly slower but provably correct, that's the one we want.

**The type system is load-bearing.** OCaml's exhaustive pattern matching means the compiler catches invalid state transitions at build time. Don't use wildcards on critical paths. If you add a new incident status, the compiler should force you to handle it everywhere. That's a feature, not an annoyance.

**Tests must pass.** `make test` must succeed before you open a PR. The existing 28 core tests and the engine replay verification are non-negotiable. If your change breaks replay determinism, something has gone properly wrong.

## Code Style

- OCaml: follow the patterns in `src/core/`. Explicit match arms, no wildcards on domain types, error cases return `Result` not exceptions.
- C: `-Wall -Werror -Wextra -pedantic`. If the compiler complains, the compiler is right.
- Keep functions short. If it doesn't fit on a screen, it probably does too many things.
- Comments should explain *why*, not *what*. The code already says what it does.

## Running Things

```bash
make              # build everything
make test         # run the core test suite
make harness      # build the stress test harness
make bench        # run 100K synthetic dispatches
make stress       # escalating stress test up to 1M dispatches
```

## Commit Messages

Write them like you're explaining the change to someone at 3am who's been debugging for six hours. Be clear, be brief, say what you changed and why. The format doesn't matter much beyond that.

## Questions?

Open an issue. There are no stupid questions, only stupid dispatch software, and we're trying to fix that.
