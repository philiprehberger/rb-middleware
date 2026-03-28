# Changelog

All notable changes to this gem will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-03-28

### Added
- Conditional middleware execution with `if:` and `unless:` guard clauses
- Per-middleware error handling with `on_error:` hook
- Skip/halt mechanism via `env[:halt] = true` and `Halt` exception
- Middleware profiling with `stack.profile(env)` returning execution timings
- Stack composition with `stack.merge(other_stack)`
- Named middleware lookup with `stack[:name]`
- Named middleware replacement with `stack.replace(name, new_middleware)`

## [0.1.2] - 2026-03-24

### Fixed
- Remove inline comments from Development section to match template

## [0.1.1] - 2026-03-22

### Changed
- Expand test coverage

## [0.1.0] - 2026-03-22

### Added
- Initial release
- Middleware stack with sequential execution
- Lambda and class-based middleware support
- Named middleware entries for targeted manipulation
- Insert before and after named entries
- Remove middleware by name
- Short-circuit capability for early termination
- Stack introspection via `to_a`
