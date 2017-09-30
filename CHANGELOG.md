# 1.0 - WIP

- **BREAKING CHANGE** Internal code for reporting status via Redis pub/sub has been removed, since it wasn't used for a long time.
- Greatly **increased performance** by avoiding redundant calls to Redis storage. Should help a lot with huge workflows spawning thousands of jobs. Previously each job loaded whole workflow instance when executed.
-  **BREAKING CHANGE** Gush is now based on ActiveJob instead of directly on Sidekiq, this allows programmers to use multiple backends, instead of just one. Including in-process or even synchronous backends. This implies following changes:
  - `Gushfile.rb` is now renamed to `Gushfile`
  - `gush` no longer knows or provides a way for starting background processes in its CLI (the `gush workers` command is now gone). This is now up to the developer.
  - `environment` option in configuration is no longer needed so was removed (it was Sidekiq specific)
-  **BREAKING CHANGE** - jobs are expected to have a `perform` method instead of `work` like in < 1.0.0 versions.
-  **BREAKING CHANGE** - `payloads` available for jobs is now an array of hashes, instead of a hash, this allows for a more flexible approach to reusing a single job in many situations. Previously payloads were grouped by predecessor's class name, so you were forced to hardcode that class name in its descendants' code.

# 0.4

- remove hard dependency on Yajl, so Gush can work with non-MRI Rubies ([#31](https://github.com/chaps-io/gush/pull/31) by [Nick Rakochy](https://github.com/chaps-io/gush/pull/31))
