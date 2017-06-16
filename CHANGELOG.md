# 1.0 - WIP

- *BREAKING CHANGE* Gush is now based on ActiveJob instead of directly on Sidekiq, this allows programmers to use multiple backends, instead of just one. Including in-process or even synchronous backends. This implies following changes:
  - `gush` no longer knows or provides a way for starting background processes in its CLI (the `gush workers` command is now gone). This is now up to the developer.
  - `environment` option in configuration is no longer needed so was removed
  -
- *BREAKING CHANGE* - jobs are expected to have a `perform` method instead of `work` like in < 1.0.0 versions.
- *BREAKING CHANGE* - `payloads` available for jobs is now an array of hashes, instead of a hash, this allows more flexible appraoach to reusing a single job in many situations. Previously payloads were grouped by predecessor's class name, so you were forced to hardcode that class name in its descendants' code.

# 0.4

- remove hard dependency on Yajl, so Gush can work with non-MRI Rubies ([#31](https://github.com/chaps-io/gush/pull/31) by [Nick Rakochy](https://github.com/chaps-io/gush/pull/31))
