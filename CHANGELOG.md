# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## Unreleased

### Added
- Add `Gush::Job#skip!` that marks a job as `#skipped?` and skips the remaining code. [See pull request](https://github.com/chaps-io/gush/pull/109).

## 2.1.0

### Added

- Allow RedisMutex’s locking duration and polling interval to be customizable, thanks to @thukim! [See pull request](https://github.com/chaps-io/gush/pull/74)
- Support for Rails 7.0 and Ruby 3.0-3.1, thanks to @joshRpowell and @kzkn!

## 2.0.1

### Fixed

- Fix bug when retried jobs didn't correctly reset their failed flag when ran again (Thanks to @theo-delaune-argus and @mickael-palma-argus! [See issue](https://github.com/chaps-io/gush/issues/61))

## 2.0.0

### Changed

- *[BREAKING]* Store gush jobs on redis hash instead of plain keys - this improves performance when retrieving keys (Thanks to @Saicheg! [See pull request](https://github.com/chaps-io/gush/pull/56))


### Added

- Allow setting queue for each job via `:queue` option in `run` method (Thanks to @devilankur18! [See pull request](https://github.com/chaps-io/gush/pull/58))


## 1.1.1 - 2018-06-09

### Changed

- Relax dependency on ActiveSupport to work with 4.2 up to 5.X (Thanks to @iacobus! [See pull request](https://github.com/chaps-io/gush/pull/54))


## 1.1.0 - 2018-02-05

### Added

- Added ability to specify TTL for Redis keys and manually expire whole workflows (Thanks to @dmitrypol! [See pull request](https://github.com/chaps-io/gush/pull/48))
- Loosened dependency on redis-rb library to >= 3.2 and < 5.0 (Thanks to @mofumofu3n! [See pull request](https://github.com/chaps-io/gush/pull/52))

### Fixed

- Improved performance of (de)serializing workflows by not storing job array inside workflow JSON and other smaller improvements ([See pull request](https://github.com/chaps-io/gush/pull/53))


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
