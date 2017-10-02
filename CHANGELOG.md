# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## 1.0.0 - 2017-10-02

### Added

-  **BREAKING CHANGE** Gush now uses ActiveJob instead of directly Sidekiq, this allows programmers to use multiple backends, instead of just one. Including in-process or even synchronous backends. See http://guides.rubyonrails.org/active_job_basics.html

### Fixed

- Fix graph rendering with `gush viz` command. Sometimes it rendered the last job detached from others, because it was using a class name instead of job name as ID.
- Fix performance problems with unserializing jobs. This greatly **increased performance** by avoiding redundant calls to Redis storage. Should help a lot with huge workflows spawning thousands of jobs. Previously each job loaded whole workflow instance when executed.

### Changed

- **BREAKING CHANGE** `Gushfile.rb` is now renamed to `Gushfile`
- **BREAKING CHANGE** Internal code for reporting status via Redis pub/sub has been removed, since it wasn't used for a long time.
- **BREAKING CHANGE** jobs are expected to have a `perform` method instead of `work` like in < 1.0.0 versions.
- **BREAKING CHANGE** `payloads` method available inside jobs is now an array of hashes, instead of a hash, this allows for a more flexible approach to reusing a single job in many situations. Previously payloads were grouped by predecessor's class name, so you were forced to hardcode that class name in its descendants' code.

### Removed

- `gush workers` command is now removed. This is now up to the developer to start background processes depending on chosen ActiveJob adapter.
- `environment` was removed since it was no longer needed (it was Sidekiq specific)

## 0.4.0

### Removed

- remove hard dependency on Yajl, so Gush can work with non-MRI Rubies ([#31](https://github.com/chaps-io/gush/pull/31) by [Nick Rakochy](https://github.com/chaps-io/gush/pull/31))
