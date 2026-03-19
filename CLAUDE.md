# CLAUDE.md

## cpanfile vs Makefile.PL dependency semantics

The `cpanfile` is used for CI testing, so dependencies there must use `requires` to ensure they are installed and tested. Even if a dependency like `LWP::UserAgent` is optional at runtime (and listed as `recommends` in `Makefile.PL`), it must remain `requires` in `cpanfile` so CI covers it.

Do not change `requires` to `recommends` in `cpanfile` for dependencies that need CI test coverage.
